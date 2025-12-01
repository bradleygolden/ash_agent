defmodule AshAgent.Runtime do
  @moduledoc """
  Runtime execution engine for AshAgent.

  This module handles the execution of agent calls by:
  1. Reading agent configuration from the DSL
  2. Extracting system prompt and messages from context
  3. Using Zoi schemas for LLM structured output
  4. Calling the configured LLM provider to generate or stream responses
  5. Parsing and validating responses with Zoi
  6. Automatically delegating to extended runtimes (like `ash_agent_tools`) when needed

  ## Context-Based Execution

  The runtime receives an `AshAgent.Context` containing messages built via generated
  functions on agent modules:

      context =
        [
          ChatAgent.instruction(company_name: "Acme"),
          ChatAgent.user(message: "Hello!")
        ]
        |> ChatAgent.context()

      {:ok, result} = AshAgent.Runtime.call(ChatAgent, context)

  ## Extension Architecture

  This runtime uses a registry pattern to support optional extensions:

  - **Without `ash_agent_tools`**: Executes agents with single-turn LLM calls
  - **With `ash_agent_tools`**: Automatically delegates to tool-calling runtime when
    agents have tools configured, enabling multi-turn agentic loops
  """

  alias AshAgent.{Context, Error, Info, ProviderRegistry}
  alias AshAgent.Runtime.{Hooks, LLMClient, PromptRenderer}
  alias AshAgent.Telemetry
  alias ReqLLM.Response
  alias Spark.Dsl.Extension

  @doc """
  Calls an agent with the given context.

  Returns `{:ok, result}` where result is an `AshAgent.Result` struct containing
  the parsed output and metadata (thinking, usage, model, etc.), or `{:error, reason}` on failure.

  ## Examples

      context =
        [
          ChatAgent.instruction(company_name: "Acme"),
          ChatAgent.user(message: "Hello!")
        ]
        |> ChatAgent.context()

      {:ok, result} = AshAgent.Runtime.call(MyApp.ChatAgent, context)
      result.output.content
      #=> "Hello! How can I assist you today?"

  """
  def call(module, %Context{} = context) do
    call(module, context, [])
  end

  def call(module, args) when is_map(args) and not is_struct(args) do
    call(module, args, [])
  end

  def call(module, args) when is_list(args) do
    call(module, Map.new(args), [])
  end

  def call(module, args, runtime_opts) when is_map(args) and not is_struct(args) do
    context = build_context_from_args(module, args)
    call(module, context, runtime_opts)
  end

  def call(module, args, runtime_opts) when is_list(args) do
    call(module, Map.new(args), runtime_opts)
  end

  def call(module, %Context{} = context, runtime_opts) do
    case resolve_tool_runtime(module) do
      {:delegate, tool_runtime} ->
        tool_runtime.call(module, context, runtime_opts)

      {:error, :missing_tool_runtime} ->
        {:error,
         Error.validation_error(
           "Tool runtime not available. This agent requires tools but no tool runtime is registered. Add a tool runtime package (like :ash_agent_tools) to your dependencies.",
           %{agent: module}
         )}

      :skip ->
        with {:ok, config} <- get_agent_config(module),
             {:ok, config} <- apply_runtime_overrides(config, runtime_opts),
             :ok <- validate_provider_capabilities(config, :call) do
          call_with_context(config, module, context)
        else
          {:error, _} = error ->
            error
        end
    end
  end

  @doc """
  Calls an agent with the given context, raising on error.
  """
  def call!(module, %Context{} = context) do
    call!(module, context, [])
  end

  def call!(module, args) when is_map(args) and not is_struct(args) do
    call!(module, args, [])
  end

  def call!(module, args) when is_list(args) do
    call!(module, Map.new(args), [])
  end

  def call!(module, %Context{} = context, runtime_opts) do
    case call(module, context, runtime_opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def call!(module, args, runtime_opts) when is_map(args) and not is_struct(args) do
    case call(module, args, runtime_opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def call!(module, args, runtime_opts) when is_list(args) do
    call!(module, Map.new(args), runtime_opts)
  end

  @doc """
  Streams an agent response with the given context.

  Returns `{:ok, stream}` where stream yields tagged chunks as they arrive,
  or `{:error, reason}` on failure.
  """
  def stream(module, %Context{} = context) do
    stream(module, context, [])
  end

  def stream(module, args) when is_map(args) and not is_struct(args) do
    stream(module, args, [])
  end

  def stream(module, args) when is_list(args) do
    stream(module, Map.new(args), [])
  end

  def stream(module, args, runtime_opts) when is_map(args) and not is_struct(args) do
    context = build_context_from_args(module, args)
    stream(module, context, runtime_opts)
  end

  def stream(module, args, runtime_opts) when is_list(args) do
    stream(module, Map.new(args), runtime_opts)
  end

  def stream(module, %Context{} = context, runtime_opts) do
    case resolve_tool_runtime(module) do
      {:delegate, tool_runtime} ->
        tool_runtime.stream(module, context, runtime_opts)

      {:error, :missing_tool_runtime} ->
        {:error,
         Error.validation_error(
           "Tool runtime not available. This agent requires tools but no tool runtime is registered. Add a tool runtime package (like :ash_agent_tools) to your dependencies.",
           %{agent: module}
         )}

      :skip ->
        with {:ok, config} <- get_agent_config(module),
             {:ok, config} <- apply_runtime_overrides(config, runtime_opts),
             :ok <- validate_provider_capabilities(config, :stream) do
          stream_with_context(config, module, context)
        else
          {:error, _} = error ->
            error
        end
    end
  end

  @doc """
  Streams an agent response with the given context, raising on error.
  """
  def stream!(module, %Context{} = context) do
    stream!(module, context, [])
  end

  def stream!(module, args) when is_map(args) and not is_struct(args) do
    stream!(module, args, [])
  end

  def stream!(module, args) when is_list(args) do
    stream!(module, Map.new(args), [])
  end

  def stream!(module, %Context{} = context, runtime_opts) do
    case stream(module, context, runtime_opts) do
      {:ok, stream} -> stream
      {:error, error} -> raise error
    end
  end

  def stream!(module, args, runtime_opts) when is_map(args) and not is_struct(args) do
    case stream(module, args, runtime_opts) do
      {:ok, stream} -> stream
      {:error, error} -> raise error
    end
  end

  def stream!(module, args, runtime_opts) when is_list(args) do
    stream!(module, Map.new(args), runtime_opts)
  end

  defp call_with_context(config, module, context) do
    {system_prompt, messages} = Context.to_provider_format(context)

    hook_context = Hooks.build_context(module, %{context: context})

    with {:ok, hook_context} <- Hooks.execute(config.hooks, :before_call, hook_context),
         hook_context = Hooks.with_prompt(hook_context, system_prompt),
         {:ok, hook_context} <- Hooks.execute(config.hooks, :after_render, hook_context),
         {:ok, schema} <- build_schema(config),
         {:ok, result} <-
           execute_call(config, module, hook_context, system_prompt, messages, schema, context) do
      hook_context = Hooks.with_response(hook_context, result)

      case Hooks.execute(config.hooks, :after_call, hook_context) do
        {:ok, hook_context} -> {:ok, hook_context.response}
        {:error, transformed_error} -> {:error, transformed_error}
      end
    else
      {:error, error} = result ->
        hook_context = Hooks.with_error(hook_context, error)

        case Hooks.execute(config.hooks, :on_error, hook_context) do
          {:ok, _context} -> result
          {:error, transformed_error} -> {:error, transformed_error}
        end
    end
  end

  defp execute_call(config, module, hook_context, system_prompt, messages, schema, context) do
    metadata = telemetry_metadata(config, module, :call)
    metadata = Map.put(metadata, :input, hook_context.input)

    if system_prompt do
      emit_prompt_rendered(metadata, system_prompt)
    end

    Telemetry.span(
      :call,
      metadata,
      fn ->
        emit_llm_request(metadata, context, nil)

        started_at = DateTime.utc_now()

        response_result =
          LLMClient.generate_object_with_messages(
            module,
            config.client,
            system_prompt,
            messages,
            schema,
            config.client_opts,
            provider_override: config.provider,
            context: context
          )

        completed_at = DateTime.utc_now()

        runtime_timing = %{
          started_at: started_at,
          completed_at: completed_at,
          duration_ms: DateTime.diff(completed_at, started_at, :millisecond)
        }

        emit_llm_response(metadata, response_result, context, nil)

        handle_call_response(response_result, config, metadata, context, runtime_timing)
      end
    )
    |> unwrap_span_result()
  end

  defp stream_with_context(config, module, context) do
    {system_prompt, messages} = Context.to_provider_format(context)

    hook_context = Hooks.build_context(module, %{context: context})

    with {:ok, hook_context} <- Hooks.execute(config.hooks, :before_call, hook_context),
         hook_context = Hooks.with_prompt(hook_context, system_prompt),
         {:ok, _hook_context} <- Hooks.execute(config.hooks, :after_render, hook_context),
         {:ok, schema} <- build_schema(config) do
      case execute_stream(config, module, system_prompt, messages, schema, context) do
        {:error, _} = error -> error
        stream -> {:ok, stream}
      end
    else
      {:error, error} = result ->
        hook_context = Hooks.with_error(hook_context, error)

        case Hooks.execute(config.hooks, :on_error, hook_context) do
          {:ok, _context} -> result
          {:error, transformed_error} -> {:error, transformed_error}
        end
    end
  end

  defp execute_stream(config, module, system_prompt, messages, schema, context) do
    metadata = telemetry_metadata(config, module, :stream)
    metadata = Map.put(metadata, :input, context)

    if system_prompt do
      emit_prompt_rendered(metadata, system_prompt)
    end

    case LLMClient.stream_object_with_messages(
           module,
           config.client,
           system_prompt,
           messages,
           schema,
           config.client_opts,
           provider_override: config.provider,
           context: context
         ) do
      {:ok, stream_response} ->
        base_metadata = Map.put(metadata, :response, stream_response)

        :telemetry.execute([:ash_agent, :stream, :start], %{}, base_metadata)

        stream_response
        |> LLMClient.stream_to_tagged_chunks(config.output_schema, config.provider)
        |> Stream.transform(
          fn -> {0, nil} end,
          fn tagged_chunk, {index, _last_result} ->
            chunk_metadata = Map.put(base_metadata, :chunk, tagged_chunk)
            :telemetry.execute([:ash_agent, :stream, :chunk], %{index: index}, chunk_metadata)
            track_stream_chunk(tagged_chunk, index)
          end,
          fn {_index, last_result} ->
            summary_metadata =
              base_metadata
              |> Map.put(:status, :ok)
              |> Map.put(:result, last_result)
              |> maybe_put_usage(config.provider, stream_response)

            :telemetry.execute([:ash_agent, :stream, :summary], %{}, summary_metadata)
            :telemetry.execute([:ash_agent, :stream, :stop], %{}, summary_metadata)
            :ok
          end
        )

      {:error, _} = error ->
        error
    end
  end

  defp get_agent_config(module) do
    {:ok, Info.agent_config(module)}
  rescue
    e ->
      {:error,
       Error.config_error("Failed to load agent configuration", %{
         module: module,
         exception: e
       })}
  end

  defp apply_runtime_overrides(config, runtime_opts) do
    opts =
      cond do
        is_map(runtime_opts) -> Map.to_list(runtime_opts)
        is_list(runtime_opts) -> runtime_opts
        true -> []
      end

    provider = Keyword.get(opts, :provider, config.provider)
    provider_changed? = provider != config.provider

    {client_value, client_override_opts} =
      case Keyword.fetch(opts, :client) do
        {:ok, {value, override_opts}} -> {value, override_opts}
        {:ok, value} -> {value, []}
        :error -> {config.client, []}
      end

    client_opts =
      if(provider_changed?, do: [], else: normalize_client_opts(config.client_opts))
      |> Keyword.merge(normalize_client_opts(client_override_opts))
      |> Keyword.merge(normalize_client_opts(Keyword.get(opts, :client_opts, [])))

    profile = Keyword.get(opts, :profile, config.profile)

    {:ok,
     %{
       config
       | client: client_value,
         client_opts: client_opts,
         provider: provider,
         profile: profile
     }}
  end

  defp normalize_client_opts(nil), do: []
  defp normalize_client_opts(opts) when is_list(opts), do: opts
  defp normalize_client_opts(%{} = map), do: Map.to_list(map)
  defp normalize_client_opts(other), do: List.wrap(other)

  defp validate_provider_capabilities(config, type) do
    features = ProviderRegistry.features(config.provider)

    cond do
      type == :stream and :streaming not in features ->
        {:error,
         Error.validation_error(
           "Provider #{inspect(config.provider)} does not support streaming",
           %{provider: config.provider}
         )}

      type == :call and :sync_call not in features ->
        {:error,
         Error.validation_error(
           "Provider #{inspect(config.provider)} does not support synchronous calls",
           %{provider: config.provider}
         )}

      true ->
        :ok
    end
  end

  defp build_schema(config) do
    case config.output_schema do
      nil ->
        {:error, Error.schema_error("No output schema configured", %{})}

      schema ->
        {:ok, schema}
    end
  end

  defp build_context_from_args(module, args) do
    {:ok, config} = get_agent_config(module)

    system_prompt =
      case config.instruction do
        nil ->
          nil

        template ->
          case PromptRenderer.render(template, args, config) do
            {:ok, rendered} -> rendered
            {:error, _} -> nil
          end
      end

    messages =
      case system_prompt do
        nil -> [AshAgent.Message.user(args)]
        prompt -> [AshAgent.Message.system(prompt), AshAgent.Message.user(args)]
      end

    Context.new(messages, input: args)
  end

  defp telemetry_metadata(config, module, type) do
    %{
      agent: module,
      client: config.client,
      provider: config.provider,
      type: type,
      output_schema: config.output_schema
    }
  end

  defp emit_prompt_rendered(metadata, rendered_prompt) do
    :telemetry.execute(
      [:ash_agent, :prompt, :rendered],
      %{},
      Map.put(metadata, :prompt, rendered_prompt)
    )
  end

  defp emit_llm_request(metadata, ctx, iteration) do
    metadata =
      metadata
      |> Map.put(:context, ctx)
      |> Map.put(:iteration, iteration)

    :telemetry.execute([:ash_agent, :llm, :request], %{}, metadata)
  end

  defp emit_llm_response(metadata, response_result, ctx, iteration) do
    metadata =
      metadata
      |> Map.put(:context, ctx)
      |> Map.put(:iteration, iteration)

    case response_result do
      {:ok, response} ->
        :telemetry.execute(
          [:ash_agent, :llm, :response],
          %{},
          Map.put(metadata, :response, response)
        )

      {:error, error} ->
        :telemetry.execute([:ash_agent, :llm, :error], %{}, Map.put(metadata, :error, error))
    end
  end

  defp track_stream_chunk({:done, result}, index), do: {[{:done, result}], {index + 1, result}}
  defp track_stream_chunk(tagged_chunk, index), do: {[tagged_chunk], {index + 1, nil}}

  defp handle_call_response({:ok, response}, config, metadata, ctx, runtime_timing) do
    case LLMClient.parse_response(config.output_schema, response) do
      {:ok, output} ->
        result = LLMClient.build_result(output, response, config.provider, runtime_timing)

        result_with_context =
          Map.put(result, :context, Context.add_assistant_message(ctx, output))

        enriched_metadata =
          build_call_metadata(metadata, {:ok, result_with_context}, response, ctx)

        {{:ok, result_with_context}, enriched_metadata}

      {:error, _} = error ->
        {error, Map.put(metadata, :context, ctx)}
    end
  end

  defp handle_call_response(error, _config, metadata, ctx, _runtime_timing) do
    {error, Map.put(metadata, :context, ctx)}
  end

  defp build_call_metadata(metadata, result, response, ctx) do
    metadata
    |> Map.put(:result, result)
    |> Map.put(:response, response)
    |> Map.put(:context, ctx)
    |> add_usage_metadata(response)
  end

  defp add_usage_metadata(metadata, %Response{} = response) do
    case response.usage do
      %{} = usage -> Map.put(metadata, :usage, usage)
      _ -> metadata
    end
  end

  defp add_usage_metadata(metadata, %AshBaml.Response{} = response) do
    case response.usage do
      %{} = usage -> Map.put(metadata, :usage, usage)
      _ -> metadata
    end
  end

  defp add_usage_metadata(metadata, _response), do: metadata

  defp maybe_put_usage(metadata, _provider, %ReqLLM.StreamResponse{}), do: metadata

  defp maybe_put_usage(metadata, _provider, %Stream{}), do: metadata

  defp maybe_put_usage(metadata, _provider, response) when is_function(response), do: metadata

  defp maybe_put_usage(metadata, provider, response) do
    case LLMClient.response_usage(provider, response) do
      nil -> metadata
      usage -> Map.put(metadata, :usage, usage)
    end
  end

  defp unwrap_span_result({result, _meta}), do: result

  defp resolve_tool_runtime(module) do
    case AshAgent.RuntimeRegistry.get_tool_runtime() do
      {:ok, handler} ->
        if handler_handles?(handler, module), do: {:delegate, handler}, else: :skip

      :error ->
        if requires_tool_runtime?(module), do: {:error, :missing_tool_runtime}, else: :skip
    end
  end

  defp handler_handles?(handler, module) do
    if function_exported?(handler, :handles?, 1) do
      handler.handles?(module)
    else
      true
    end
  rescue
    _ -> false
  end

  defp requires_tool_runtime?(module) do
    Extension.get_persisted(module, :requires_tool_runtime?, false)
  rescue
    _ -> false
  end
end
