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

  alias AshAgent.{Conversation, Error, Info, ToolConverter}
  alias AshAgent.Runtime.{Hooks, LLMClient, ToolExecutor}
  alias AshAgent.Runtime.PromptRenderer
  alias AshAgent.SchemaConverter
  alias AshAgent.Telemetry
  alias ReqLLM.Response
  alias Spark.Dsl.Extension

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
    domain = get_domain(module)

    rendered_prompt =
      if prompt do
        case PromptRenderer.render(prompt, context.input, config) do
          {:ok, rendered} -> rendered
          {:error, _} -> nil
        end
      else
        nil
      end

    conversation =
      Conversation.new(module, context.input,
        domain: domain,
        actor: Map.get(context, :actor),
        tenant: Map.get(context, :tenant),
        max_iterations: tool_config.max_iterations,
        system_prompt: rendered_prompt
      )

    execute_tool_calling_loop(
      config,
      module,
      context,
      prompt,
      schema,
      tools,
      conversation,
      tool_config
    )
  end

  defp execute_tool_calling_loop(
         config,
         module,
         context,
         prompt,
         schema,
         tools,
         conversation,
         tool_config
       ) do
    if Conversation.exceeded_max_iterations?(conversation) do
      {:error, Error.llm_error("Max iterations (#{conversation.max_iterations}) exceeded")}
    else
      messages = Conversation.to_messages(conversation)
      current_prompt = nil

      case Telemetry.span(
             :call,
             telemetry_metadata(config, module, :call),
             fn ->
               LLMClient.generate_object(
                 module,
                 config.client,
                 current_prompt,
                 schema,
                 config.client_opts,
                 context,
                 tools,
                 messages
               )
             end
           ) do
        {:ok, response} ->
          handle_llm_response(
            response,
            config,
            module,
            context,
            prompt,
            schema,
            tools,
            conversation,
            tool_config
          )

        {:error, _reason} = error ->
          if tool_config.on_error == :continue do
            conversation = Conversation.add_assistant_message(conversation, "", [])

            execute_tool_calling_loop(
              config,
              module,
              context,
              prompt,
              schema,
              tools,
              conversation,
              tool_config
            )
          else
            error
          end
      end
    end
  end

  defp handle_llm_response(
         response,
         config,
         module,
         context,
         prompt,
         schema,
         tools,
         conversation,
         tool_config
       ) do
    tool_calls = extract_tool_calls(response, config.provider)
    content = extract_content(response, config.provider)

    conversation = Conversation.add_assistant_message(conversation, content, tool_calls)

    case tool_calls do
      [] ->
        case convert_baml_response_to_output(response, config.output_type, config.provider) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end

      tool_calls ->
        results = ToolExecutor.execute_tools(tool_calls, config.tools, conversation)

        if tool_config.on_error == :halt and
             Enum.any?(results, fn
               {_, {_, :error}} -> true
               _ -> false
             end) do
          {:error, Error.llm_error("Tool execution failed")}
        else
          conversation = Conversation.add_tool_results(conversation, results)

          execute_tool_calling_loop(
            config,
            module,
            context,
            prompt,
            schema,
            tools,
            conversation,
            tool_config
          )
        end
    end
  end

  defp convert_baml_response_to_output(response, output_type, provider)
       when provider in [:baml, AshAgent.Providers.Baml] do
    convert_baml_union_to_output(response, output_type)
  end

  defp convert_baml_response_to_output(response, output_type, _provider) do
    LLMClient.parse_response(output_type, response)
  end

  defp convert_baml_union_to_output(%_{} = response, output_type) do
    struct_map = Map.from_struct(response)
    struct_name = response.__struct__ |> Module.split() |> List.last()

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

  defp convert_baml_union_to_output(response, output_type) do
    LLMClient.parse_response(output_type, response)
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

    cond do
      String.contains?(struct_name, "ToolCall") and not String.contains?(struct_name, "Response") ->
        ""

      Map.has_key?(struct_map, :tool_name) or Map.has_key?(struct_map, :tool_arguments) ->
        ""

      Map.has_key?(struct_map, :__type__) and struct_map.__type__ in ["tool_call", "ToolCall"] ->
        ""

      Map.has_key?(struct_map, :content) ->
        content = struct_map.content
        if is_binary(content), do: content, else: ""

      true ->
        ""
    end
  end

  defp extract_baml_content(_response) do
    ""
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

    cond do
      String.contains?(struct_name, "ToolCall") and not String.contains?(struct_name, "Response") ->
        cond do
          Map.has_key?(struct_map, :tool_name) ->
            tool_name = struct_map.tool_name
            args = Map.get(struct_map, :tool_arguments) || Map.get(struct_map, :arguments) || %{}

            [
              %{
                id: generate_tool_call_id(),
                name: normalize_tool_name(tool_name),
                arguments: normalize_baml_args(args)
              }
            ]

          Map.has_key?(struct_map, :name) ->
            name = struct_map.name
            args = Map.get(struct_map, :arguments) || %{}

            [
              %{
                id: generate_tool_call_id(),
                name: normalize_tool_name(name),
                arguments: normalize_baml_args(args)
              }
            ]

          true ->
            []
        end

      Map.has_key?(struct_map, :tool_name) ->
        tool_name = struct_map.tool_name
        args = Map.get(struct_map, :tool_arguments) || Map.get(struct_map, :arguments) || %{}

        [
          %{
            id: generate_tool_call_id(),
            name: normalize_tool_name(tool_name),
            arguments: normalize_baml_args(args)
          }
        ]

      true ->
        []
    end
  end

  defp extract_baml_tool_calls(_response) do
    []
  end

  defp normalize_tool_name(name) when is_atom(name), do: name

  defp normalize_tool_name(name) when is_binary(name) do
    try do
      String.to_existing_atom(name)
    rescue
      ArgumentError -> name
    end
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
end
