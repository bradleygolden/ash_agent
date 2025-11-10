defmodule AshAgent.Runtime do
  @moduledoc """
  Runtime execution engine for AshAgent.

  This module handles the execution of agent calls by:
  1. Reading agent configuration from the DSL
  2. Rendering prompt templates with provided arguments
  3. Converting TypedStruct definitions to req_llm schemas
  4. Calling ReqLLM to generate or stream responses
  5. Parsing and returning structured results
  """

  alias AshAgent.{Context, Error, Info, ToolConverter}
  alias AshAgent.Runtime.{DefaultHooks, Hooks, LLMClient, ToolExecutor}
  alias AshAgent.Runtime.PromptRenderer
  alias AshAgent.SchemaConverter
  alias AshAgent.Telemetry
  alias ReqLLM.Response
  alias Spark.Dsl.Extension

  defmodule LoopState do
    @moduledoc false
    defstruct [
      :config,
      :module,
      :context,
      :prompt,
      :schema,
      :tools,
      :tool_config
    ]
  end

  @doc """
  Calls an agent with the given arguments.

  Returns `{:ok, result}` where result is an instance of the agent's output TypedStruct,
  or `{:error, reason}` on failure.

  ## Examples

      # Define an agent resource
      defmodule MyApp.ChatAgent do
        use Ash.Resource,
          domain: MyApp.Domain,
          extensions: [AshAgent.Resource]

        defmodule Reply do
          use Ash.TypedStruct

          typed_struct do
            field :content, :string, enforce: true
          end
        end

        agent do
          client "anthropic:claude-3-5-sonnet"
          output Reply
          prompt "You are a helpful assistant. Reply to: {{ message }}"
        end

        input do
          argument :message, :string
        end
      end

      # Call the agent
      {:ok, reply} = AshAgent.Runtime.call(MyApp.ChatAgent, message: "Hello!")
      reply.content
      #=> "Hello! How can I assist you today?"

  """
  @spec call(module(), keyword() | map()) :: {:ok, struct()} | {:error, term()}
  def call(module, args) do
    case get_agent_config(module) do
      {:ok, config} ->
        call_with_hooks(config, module, args)

      {:error, _} = error ->
        error
    end
  end

  defp call_with_hooks(config, module, args) do
    context = Hooks.build_context(module, args)

    with {:ok, context} <- Hooks.execute(config.hooks, :before_call, context),
         {:ok, prompt} <- render_prompt(config, context.input),
         context = Hooks.with_prompt(context, prompt),
         {:ok, context} <- Hooks.execute(config.hooks, :after_render, context),
         {:ok, schema} <- build_schema(config),
         {:ok, result} <-
           execute_with_tools(config, module, context, prompt, schema) do
      context = Hooks.with_response(context, result)

      case Hooks.execute(config.hooks, :after_call, context) do
        {:ok, context} -> {:ok, context.response}
        {:error, transformed_error} -> {:error, transformed_error}
      end
    else
      {:error, error} = result ->
        context = Hooks.with_error(context, error)

        case Hooks.execute(config.hooks, :on_error, context) do
          {:ok, _context} -> result
          {:error, transformed_error} -> {:error, transformed_error}
        end
    end
  end

  defp execute_with_tools(config, module, context, prompt, schema) do
    if config.tools != [] do
      execute_with_tool_calling(config, module, context, prompt, schema)
    else
      execute_single_turn(config, module, context, prompt, schema)
    end
  end

  defp execute_single_turn(config, module, context, prompt, schema) do
    Telemetry.span(
      :call,
      telemetry_metadata(config, module, :call),
      fn ->
        LLMClient.generate_object(
          module,
          config.client,
          prompt,
          schema,
          config.client_opts,
          context,
          nil,
          nil
        )
      end
    )
    |> then(fn
      {:ok, response} ->
        LLMClient.parse_response(config.output_type, response)

      error ->
        error
    end)
  end

  defp execute_with_tool_calling(config, module, context, prompt, schema) do
    tools = ToolConverter.to_json_schema(config.tools)
    tool_config = config.tool_config

    rendered_prompt =
      if prompt do
        case PromptRenderer.render(prompt, context.input, config) do
          {:ok, rendered} -> rendered
          {:error, _} -> nil
        end
      else
        nil
      end

    ctx = Context.new(context.input, system_prompt: rendered_prompt)

    loop_state = %LoopState{
      config: config,
      module: module,
      context: context,
      prompt: prompt,
      schema: schema,
      tools: tools,
      tool_config: tool_config
    }

    execute_tool_calling_loop(loop_state, ctx)
  end

  defp execute_tool_calling_loop(%LoopState{} = state, ctx) do
    case execute_on_iteration_start_hook(ctx, state) do
      {:ok, _ctx} ->
        result = execute_tool_calling_iteration(state, ctx)
        execute_on_iteration_complete_hook(ctx, result, state)
        result

      {:error, _reason} = error ->
        error
    end
  end

  defp execute_tool_calling_iteration(%LoopState{} = state, ctx) do
    ctx = execute_prepare_context_hook(ctx, state)
    messages = Context.to_messages(ctx)
    messages = execute_prepare_messages_hook(messages, ctx, state)
    current_prompt = nil

    case Telemetry.span(
           :call,
           telemetry_metadata(state.config, state.module, :call),
           fn ->
             LLMClient.generate_object(
               state.module,
               state.config.client,
               current_prompt,
               state.schema,
               state.config.client_opts,
               state.context,
               state.tools,
               messages
             )
           end
         ) do
      {:ok, response} ->
        handle_llm_response(response, state, ctx)

      {:error, _reason} = error ->
        handle_tool_calling_error(error, state, ctx)
    end
  end

  defp handle_tool_calling_error(error, %LoopState{} = state, ctx) do
    if state.tool_config.on_error == :continue do
      ctx = Context.add_assistant_message(ctx, "", [])
      execute_tool_calling_loop(state, ctx)
    else
      error
    end
  end

  defp handle_llm_response(response, %LoopState{} = state, ctx) do
    tool_calls = extract_tool_calls(response, state.config.provider)
    content = extract_content(response, state.config.provider)

    ctx = Context.add_assistant_message(ctx, content, tool_calls)

    ctx =
      case LLMClient.response_usage(response) do
        nil ->
          ctx

        usage ->
          Context.add_token_usage(ctx, usage)
      end

    case tool_calls do
      [] ->
        convert_baml_response_to_output(response, state.config.output_type, state.config.provider)

      calls when is_list(calls) ->
        execute_tool_calls(calls, state, ctx)
    end
  end

  defp execute_tool_calls(tool_calls, %LoopState{} = state, ctx) do
    runtime_context = %{
      agent: state.module,
      domain: get_domain(state.module),
      actor: Map.get(state.context, :actor),
      tenant: Map.get(state.context, :tenant)
    }

    results = ToolExecutor.execute_tools(tool_calls, state.config.tools, runtime_context)
    results = execute_prepare_tool_results_hook(results, tool_calls, ctx, state)

    if has_tool_errors?(results, state.tool_config) do
      {:error, Error.llm_error("Tool execution failed")}
    else
      ctx = Context.add_tool_results(ctx, results)
      execute_tool_calling_loop(state, ctx)
    end
  end

  defp has_tool_errors?(results, tool_config) do
    tool_config.on_error == :halt and
      Enum.any?(results, fn
        {_, {_, :error}} -> true
        _ -> false
      end)
  end

  defp convert_baml_response_to_output(response, output_type, provider)
       when provider in [:baml, AshAgent.Providers.Baml] do
    convert_baml_union_to_output(response, output_type)
  end

  defp convert_baml_response_to_output(response, output_type, _provider) do
    LLMClient.parse_response(output_type, response)
  end

  defp convert_baml_union_to_output(%_{} = response, output_type) do
    struct_module = response.__struct__

    if Map.has_key?(response, :data) and function_exported?(struct_module, :usage, 1) do
      convert_baml_union_to_output(response.data, output_type)
    else
      struct_map = Map.from_struct(response)
      struct_name = struct_module |> Module.split() |> List.last()

      handle_baml_struct(response, struct_map, struct_name, output_type)
    end
  end

  defp convert_baml_union_to_output(response, output_type) do
    LLMClient.parse_response(output_type, response)
  end

  defp handle_baml_struct(response, struct_map, struct_name, output_type) do
    cond do
      String.contains?(struct_name, "ToolCallResponse") ->
        case Map.take(struct_map, [:content, :confidence]) do
          data when map_size(data) > 0 ->
            {:ok, struct(output_type, data)}

          _ ->
            LLMClient.parse_response(output_type, response)
        end

      Map.has_key?(struct_map, :content) and not Map.has_key?(struct_map, :tool_name) ->
        case Map.take(struct_map, [:content, :confidence]) do
          data when map_size(data) > 0 ->
            {:ok, struct(output_type, data)}

          _ ->
            LLMClient.parse_response(output_type, response)
        end

      true ->
        LLMClient.parse_response(output_type, response)
    end
  rescue
    e ->
      {:error,
       Error.parse_error("Failed to convert BAML response to output type", %{
         output_type: output_type,
         response: response,
         exception: e
       })}
  end

  defp extract_content(response, provider) when provider in [:baml, AshAgent.Providers.Baml] do
    extract_baml_content(response)
  end

  defp extract_content(%Response{} = response, _provider) do
    case ReqLLM.Response.unwrap_object(response) do
      {:ok, object} when is_map(object) ->
        case Map.get(object, "content") || Map.get(object, :content) do
          nil -> ""
          content when is_binary(content) -> content
          content when is_list(content) -> extract_text_from_content(content)
          _ -> ""
        end

      _ ->
        ""
    end
  end

  defp extract_content(%{content: content}, _provider) when is_binary(content), do: content
  defp extract_content(%{"content" => content}, _provider) when is_binary(content), do: content
  defp extract_content(_response, _provider), do: ""

  defp extract_baml_content(%_{} = response) do
    struct_name = response.__struct__ |> Module.split() |> List.last()
    struct_map = Map.from_struct(response)

    if baml_is_tool_call?(struct_name, struct_map) do
      ""
    else
      extract_content_field(struct_map)
    end
  end

  defp extract_baml_content(_response), do: ""

  defp baml_is_tool_call?(struct_name, struct_map) do
    tool_call_struct?(struct_name) or
      has_tool_fields?(struct_map) or
      has_tool_call_type?(struct_map)
  end

  defp tool_call_struct?(struct_name) do
    String.contains?(struct_name, "ToolCall") and not String.contains?(struct_name, "Response")
  end

  defp has_tool_fields?(struct_map) do
    Map.has_key?(struct_map, :tool_name) or Map.has_key?(struct_map, :tool_arguments)
  end

  defp has_tool_call_type?(struct_map) do
    Map.has_key?(struct_map, :__type__) and struct_map.__type__ in ["tool_call", "ToolCall"]
  end

  defp extract_content_field(struct_map) do
    case Map.get(struct_map, :content) do
      content when is_binary(content) -> content
      _ -> ""
    end
  end

  defp extract_text_from_content([%{"type" => "text", "text" => text} | _]) when is_binary(text),
    do: text

  defp extract_text_from_content([%{type: "text", text: text} | _]) when is_binary(text), do: text
  defp extract_text_from_content([_ | rest]), do: extract_text_from_content(rest)
  defp extract_text_from_content([]), do: ""

  defp extract_tool_calls(response, provider) when provider in [:baml, AshAgent.Providers.Baml] do
    extract_baml_tool_calls(response)
  end

  defp extract_tool_calls(%Response{} = response, _provider) do
    case Response.tool_calls(response) do
      nil -> []
      tool_calls -> normalize_tool_calls(tool_calls)
    end
  end

  defp extract_tool_calls(%{tool_calls: tool_calls}, _provider) when is_list(tool_calls) do
    normalize_tool_calls(tool_calls)
  end

  defp extract_tool_calls(_response, _provider) do
    []
  end

  defp extract_baml_tool_calls(%_{} = response) do
    struct_map = Map.from_struct(response)
    struct_name = response.__struct__ |> Module.split() |> List.last()

    if tool_call_struct?(struct_name) do
      extract_tool_call_from_struct(struct_map)
    else
      extract_tool_call_from_map(struct_map)
    end
  end

  defp extract_baml_tool_calls(_response), do: []

  defp extract_tool_call_from_struct(struct_map) do
    cond do
      Map.has_key?(struct_map, :tool_name) ->
        build_tool_call(struct_map.tool_name, get_tool_arguments(struct_map))

      Map.has_key?(struct_map, :name) ->
        build_tool_call(struct_map.name, Map.get(struct_map, :arguments, %{}))

      true ->
        []
    end
  end

  defp extract_tool_call_from_map(struct_map) do
    if Map.has_key?(struct_map, :tool_name) do
      build_tool_call(struct_map.tool_name, get_tool_arguments(struct_map))
    else
      []
    end
  end

  defp get_tool_arguments(struct_map) do
    Map.get(struct_map, :tool_arguments) || Map.get(struct_map, :arguments) || %{}
  end

  defp build_tool_call(name, args) do
    [
      %{
        id: generate_tool_call_id(),
        name: normalize_tool_name(name),
        arguments: normalize_baml_args(args)
      }
    ]
  end

  defp normalize_tool_name(name) when is_atom(name), do: name

  defp normalize_tool_name(name) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> name
  end

  defp normalize_tool_name(name), do: name

  defp normalize_baml_args(args) when is_map(args) do
    Enum.into(args, %{}, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp normalize_baml_args(args) when is_binary(args) do
    case Jason.decode!(args) do
      map when is_map(map) ->
        Enum.into(map, %{}, fn
          {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
          {k, v} -> {k, v}
        end)

      other ->
        other
    end
  end

  defp normalize_baml_args(args) when is_struct(args), do: Map.from_struct(args)
  defp normalize_baml_args(args), do: args

  defp generate_tool_call_id do
    "call_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp normalize_tool_calls(tool_calls) do
    Enum.map(tool_calls, fn
      %{id: id, name: name, arguments: args} when is_binary(args) ->
        %{id: id, name: name, arguments: Jason.decode!(args)}

      %{"id" => id, "name" => name, "arguments" => args} when is_binary(args) ->
        %{id: id, name: name, arguments: Jason.decode!(args)}

      tool_call ->
        tool_call
    end)
  end

  defp get_domain(module) do
    case Ash.Resource.Info.domain(module) do
      nil -> nil
      domain -> domain
    end
  end

  @doc """
  Calls an agent with the given arguments, raising on error.

  Returns the result struct directly or raises an exception.
  """
  @spec call!(module(), keyword() | map()) :: struct() | no_return()
  def call!(module, args) do
    case call(module, args) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Streams an agent response with the given arguments.

  Returns `{:ok, stream}` where stream yields partial results,
  or `{:error, reason}` on failure.

  Note: For structured outputs, the stream completes when the full JSON object
  is received, as complete JSON is required for parsing into the TypedStruct.

  ## Examples

      # Using the same ChatAgent from call/2 example
      {:ok, stream} = AshAgent.Runtime.stream(MyApp.ChatAgent, message: "Hello!")

      # The stream yields the complete structured result
      results = Enum.to_list(stream)
      [reply] = results
      reply.content
      #=> "Hello! How can I assist you today?"

  """
  @spec stream(module(), keyword() | map()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(module, args) do
    case get_agent_config(module) do
      {:ok, config} ->
        stream_with_hooks(config, module, args)

      {:error, _} = error ->
        error
    end
  end

  defp stream_with_hooks(config, module, args) do
    context = Hooks.build_context(module, args)

    with {:ok, context} <- Hooks.execute(config.hooks, :before_call, context),
         {:ok, prompt} <- render_prompt(config, context.input),
         context = Hooks.with_prompt(context, prompt),
         {:ok, context} <- Hooks.execute(config.hooks, :after_render, context),
         {:ok, schema} <- build_schema(config),
         {:ok, stream_response} <-
           Telemetry.span(
             :stream,
             telemetry_metadata(config, module, :stream),
             fn ->
               LLMClient.stream_object(
                 module,
                 config.client,
                 context.rendered_prompt,
                 schema,
                 config.client_opts,
                 context
               )
             end
           ) do
      stream = LLMClient.stream_to_structs(stream_response, config.output_type)

      wrapped_stream =
        Stream.map(stream, fn result ->
          context = Hooks.with_response(context, result)

          case Hooks.execute(config.hooks, :after_call, context) do
            {:ok, context} -> context.response
            {:error, _} -> result
          end
        end)

      {:ok, wrapped_stream}
    else
      {:error, error} = result ->
        context = Hooks.with_error(context, error)

        case Hooks.execute(config.hooks, :on_error, context) do
          {:ok, _context} -> result
          {:error, transformed_error} -> {:error, transformed_error}
        end
    end
  end

  @doc """
  Streams an agent response with the given arguments, raising on error.

  Returns a stream that yields partial results or raises an exception.
  """
  @spec stream!(module(), keyword() | map()) :: Enumerable.t() | no_return()
  def stream!(module, args) do
    case stream(module, args) do
      {:ok, stream} -> stream
      {:error, error} -> raise error
    end
  end

  defp get_agent_config(module) do
    {client_string, client_opts} = Extension.get_opt(module, [:agent], :client, nil, true)
    tool_config = Info.tool_config(module)
    tools = Info.tools(module)

    config = %{
      client: client_string,
      client_opts: client_opts,
      provider: Extension.get_opt(module, [:agent], :provider, :req_llm),
      prompt: Extension.get_opt(module, [:agent], :prompt, nil, true),
      output_type: get_output_type(module),
      input_args: get_input_args(module),
      hooks: Extension.get_opt(module, [:agent], :hooks, nil, true),
      tools: tools,
      tool_config: tool_config
    }

    {:ok, config}
  rescue
    e ->
      {:error,
       Error.config_error("Failed to load agent configuration", %{
         module: module,
         exception: e
       })}
  end

  defp get_output_type(module) do
    Extension.get_opt(module, [:agent], :output, nil, true)
  end

  defp get_input_args(module) do
    Extension.get_entities(module, [:agent, :input])
  end

  @spec render_prompt(map(), keyword() | map()) :: {:ok, String.t()} | {:error, String.t()}
  defp render_prompt(%{prompt: nil}, _args), do: {:ok, nil}

  defp render_prompt(config, args) do
    PromptRenderer.render(config.prompt, args, config)
  end

  defp build_schema(%{provider: provider} = config) do
    if schema_required?(provider) do
      case config.output_type do
        nil ->
          {:error, Error.schema_error("No output type defined for agent")}

        type_module ->
          schema = SchemaConverter.to_req_llm_schema(type_module)
          {:ok, schema}
      end
    else
      {:ok, nil}
    end
  rescue
    e ->
      {:error,
       Error.schema_error("Failed to build schema", %{
         output_type: config.output_type,
         exception: e
       })}
  end

  defp schema_required?(provider) do
    provider not in [:baml, AshAgent.Providers.Baml]
  end

  defp telemetry_metadata(config, module, type) do
    %{
      agent: module,
      provider: config.provider,
      client: config.client,
      type: type
    }
  end

  defp execute_prepare_tool_results_hook(results, tool_calls, ctx, %LoopState{} = state) do
    if state.config.hooks do
      hook_context = %{
        agent: state.module,
        iteration: ctx.current_iteration,
        tool_calls: tool_calls,
        results: results,
        context: ctx,
        token_usage: Context.get_cumulative_tokens(ctx)
      }

      case Hooks.execute(state.config.hooks, :prepare_tool_results, hook_context) do
        {:ok, updated_results} when is_list(updated_results) ->
          updated_results

        {:ok, ^hook_context} ->
          # Hook not implemented, Hooks.execute returned the context map as-is
          results

        {:error, reason} ->
          require Logger

          Logger.warning(
            "prepare_tool_results hook failed: #{inspect(reason)}, using original results"
          )

          :telemetry.execute(
            [:ash_agent, :hook, :error],
            %{},
            %{hook_name: :prepare_tool_results, error: reason}
          )

          results
      end
    else
      results
    end
  end

  defp execute_prepare_context_hook(ctx, %LoopState{} = state) do
    if state.config.hooks do
      hook_context = %{
        agent: state.module,
        context: ctx,
        token_usage: Context.get_cumulative_tokens(ctx),
        iteration: ctx.current_iteration
      }

      case Hooks.execute(state.config.hooks, :prepare_context, hook_context) do
        {:ok, %AshAgent.Context{} = updated_ctx} ->
          updated_ctx

        {:ok, ^hook_context} ->
          # Hook not implemented, Hooks.execute returned the context map as-is
          ctx

        {:error, reason} ->
          require Logger

          Logger.warning(
            "prepare_context hook failed: #{inspect(reason)}, using original context"
          )

          :telemetry.execute(
            [:ash_agent, :hook, :error],
            %{},
            %{hook_name: :prepare_context, error: reason}
          )

          ctx
      end
    else
      ctx
    end
  end

  defp execute_prepare_messages_hook(messages, ctx, %LoopState{} = state) do
    if state.config.hooks do
      hook_context = %{
        agent: state.module,
        context: ctx,
        messages: messages,
        tools: state.tools,
        iteration: ctx.current_iteration
      }

      case Hooks.execute(state.config.hooks, :prepare_messages, hook_context) do
        {:ok, updated_messages} when is_list(updated_messages) ->
          updated_messages

        {:ok, ^hook_context} ->
          # Hook not implemented, Hooks.execute returned the context map as-is
          messages

        {:error, reason} ->
          require Logger

          Logger.warning(
            "prepare_messages hook failed: #{inspect(reason)}, using original messages"
          )

          :telemetry.execute(
            [:ash_agent, :hook, :error],
            %{},
            %{hook_name: :prepare_messages, error: reason}
          )

          messages
      end
    else
      messages
    end
  end

  defp execute_on_iteration_start_hook(ctx, %LoopState{} = state) do
    hook_context = %{
      agent: state.module,
      iteration_number: ctx.current_iteration,
      context: ctx,
      result: nil,
      token_usage: Context.get_cumulative_tokens(ctx),
      max_iterations: state.tool_config.max_iterations,
      client: state.config.client
    }

    :telemetry.execute(
      [:ash_agent, :hook, :start],
      %{},
      %{hook_name: :on_iteration_start}
    )

    start_time = System.monotonic_time()

    result =
      if state.config.hooks do
        Hooks.execute(state.config.hooks, :on_iteration_start, hook_context)
      else
        DefaultHooks.on_iteration_start(hook_context)
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:ash_agent, :hook, :stop],
      %{duration: duration},
      %{hook_name: :on_iteration_start}
    )

    result
  end

  defp execute_on_iteration_complete_hook(ctx, iteration_result, %LoopState{} = state) do
    hook_context = %{
      agent: state.module,
      iteration_number: ctx.current_iteration,
      context: ctx,
      result: iteration_result,
      token_usage: Context.get_cumulative_tokens(ctx),
      max_iterations: state.tool_config.max_iterations,
      client: state.config.client
    }

    :telemetry.execute(
      [:ash_agent, :hook, :start],
      %{},
      %{hook_name: :on_iteration_complete}
    )

    start_time = System.monotonic_time()

    result =
      if state.config.hooks do
        Hooks.execute(state.config.hooks, :on_iteration_complete, hook_context)
      else
        DefaultHooks.on_iteration_complete(hook_context)
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:ash_agent, :hook, :stop],
      %{duration: duration},
      %{hook_name: :on_iteration_complete}
    )

    case result do
      {:error, reason} ->
        require Logger

        Logger.warning(
          "on_iteration_complete hook failed: #{inspect(reason)}, continuing iteration"
        )

        :telemetry.execute(
          [:ash_agent, :hook, :error],
          %{},
          %{hook_name: :on_iteration_complete, error: reason}
        )

      _ ->
        :ok
    end

    :ok
  end
end
