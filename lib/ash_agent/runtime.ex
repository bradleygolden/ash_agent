defmodule AshAgent.Runtime do
  @moduledoc """
  Runtime execution engine for AshAgent.

  This module handles the execution of agent calls by:
  1. Reading agent configuration from the DSL
  2. Rendering prompt templates with provided arguments
  3. Converting TypedStruct definitions to LLM schemas
  4. Calling the configured LLM provider to generate or stream responses
  5. Parsing and returning structured results
  6. Automatically delegating to extended runtimes (like `ash_agent_tools`) when needed

  ## Extension Architecture

  This runtime uses a registry pattern to support optional extensions:

  - **Without `ash_agent_tools`**: Executes agents with single-turn LLM calls
  - **With `ash_agent_tools`**: Automatically delegates to tool-calling runtime when
    agents have tools configured, enabling multi-turn agentic loops

  Users always call `AshAgent.Runtime.call/2` regardless of which packages are installed.
  The runtime automatically uses the appropriate execution strategy.

  ## Example

      # Works with or without ash_agent_tools installed
      {:ok, result} = AshAgent.Runtime.call(MyAgent, args)

  """

  alias AshAgent.{Error, Info, ProviderRegistry}
  alias AshAgent.Runtime.{Hooks, LLMClient, PromptRenderer}
  alias AshAgent.SchemaConverter
  alias AshAgent.Telemetry
  alias ReqLLM.Response
  alias Spark.Dsl.Extension

  @doc """
  Calls an agent with the given arguments.

  Returns `{:ok, result}` where result is an `AshAgent.Result` struct containing
  the parsed output and metadata (thinking, usage, model, etc.), or `{:error, reason}` on failure.

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
      {:ok, result} = AshAgent.Runtime.call(MyApp.ChatAgent, message: "Hello!")
      result.output.content
      #=> "Hello! How can I assist you today?"

      # Access thinking content (if extended thinking is enabled)
      result.thinking
      #=> "The user greeted me, I should respond warmly..."

      # Access usage metadata
      result.usage
      #=> %{input_tokens: 10, output_tokens: 5, total_tokens: 15}

  """
  @spec call(module(), keyword() | map()) :: {:ok, AshAgent.Result.t()} | {:error, term()}
  def call(module, args) do
    call(module, args, [])
  end

  @spec call(module(), keyword() | map(), keyword() | map()) ::
          {:ok, AshAgent.Result.t()} | {:error, term()}
  def call(module, args, runtime_opts) do
    case resolve_tool_runtime(module) do
      {:delegate, tool_runtime} ->
        tool_runtime.call(module, args, runtime_opts)

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
          call_with_hooks(config, module, args)
        else
          {:error, _} = error ->
            error
        end
    end
  end

  @doc """
  Calls an agent with the given arguments, raising on error.

  Returns the result directly or raises an exception.

  See `call/2` for usage examples.
  """
  @spec call!(module(), keyword() | map()) :: AshAgent.Result.t() | no_return()
  def call!(module, args) do
    call!(module, args, [])
  end

  @spec call!(module(), keyword() | map(), keyword() | map()) :: AshAgent.Result.t() | no_return()
  def call!(module, args, runtime_opts) do
    case call(module, args, runtime_opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Streams an agent response with the given arguments.

  Returns `{:ok, stream}` where stream yields tagged chunks as they arrive,
  or `{:error, reason}` on failure.

  ## Tagged Chunk Types

  - `{:thinking, text}` - thinking/reasoning content (if extended thinking is enabled)
  - `{:content, struct}` - partial content struct as it's being generated
  - `{:tool_call, chunk}` - tool call request from the model
  - `{:done, result}` - final `AshAgent.Result` struct with full metadata

  ## Examples

      # Stream responses with tagged chunks
      {:ok, stream} = AshAgent.Runtime.stream(MyApp.ChatAgent, message: "Hello!")

      stream
      |> Stream.each(fn
        {:thinking, text} ->
          IO.puts("Thinking: \#{text}")
        {:content, partial} ->
          IO.puts("Content: \#{partial.content}")
        {:done, result} ->
          IO.puts("Final: \#{result.output.content}")
          IO.puts("Thinking: \#{result.thinking}")
      end)
      |> Stream.run()

  """
  @spec stream(module(), keyword() | map()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(module, args) do
    stream(module, args, [])
  end

  @spec stream(module(), keyword() | map(), keyword() | map()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream(module, args, runtime_opts) do
    case resolve_tool_runtime(module) do
      {:delegate, tool_runtime} ->
        tool_runtime.stream(module, args, runtime_opts)

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
          stream_with_hooks(config, module, args)
        else
          {:error, _} = error ->
            error
        end
    end
  end

  @doc """
  Streams an agent response with the given arguments, raising on error.

  Returns a stream that yields partial results or raises an exception.
  """
  @spec stream!(module(), keyword() | map()) :: Enumerable.t() | no_return()
  def stream!(module, args) do
    stream!(module, args, [])
  end

  @spec stream!(module(), keyword() | map(), keyword() | map()) :: Enumerable.t() | no_return()
  def stream!(module, args, runtime_opts) do
    case stream(module, args, runtime_opts) do
      {:ok, stream} -> stream
      {:error, error} -> raise error
    end
  end

  # Private functions

  defp call_with_hooks(config, module, args) do
    context = Hooks.build_context(module, args)

    with {:ok, context} <- Hooks.execute(config.hooks, :before_call, context),
         {:ok, prompt} <- render_prompt(config, context.input),
         context = Hooks.with_prompt(context, prompt),
         {:ok, context} <- Hooks.execute(config.hooks, :after_render, context),
         {:ok, schema} <- build_schema(config),
         {:ok, result} <- execute_call(config, module, context, prompt, schema) do
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

  defp execute_call(config, module, context, prompt, schema) do
    metadata = telemetry_metadata(config, module, :call)
    metadata = Map.put(metadata, :input, context.input)

    rendered_prompt =
      if prompt do
        case PromptRenderer.render(prompt, context.input, config) do
          {:ok, rendered} -> rendered
          {:error, _} -> nil
        end
      else
        nil
      end

    if rendered_prompt do
      emit_prompt_rendered(metadata, rendered_prompt)
    end

    ctx = context_module().new(context.input, system_prompt: rendered_prompt)

    Telemetry.span(
      :call,
      metadata,
      fn ->
        emit_llm_request(metadata, ctx, nil)

        response_result =
          LLMClient.generate_object(
            module,
            config.client,
            prompt,
            schema,
            config.client_opts,
            context,
            provider_override: config.provider
          )

        emit_llm_response(metadata, response_result, ctx, nil)

        handle_call_response(response_result, config, metadata, ctx)
      end
    )
    |> unwrap_span_result()
  end

  defp stream_with_hooks(config, module, args) do
    context = Hooks.build_context(module, args)

    with {:ok, context} <- Hooks.execute(config.hooks, :before_call, context),
         {:ok, prompt} <- render_prompt(config, context.input),
         context = Hooks.with_prompt(context, prompt),
         {:ok, context} <- Hooks.execute(config.hooks, :after_render, context),
         {:ok, schema} <- build_schema(config) do
      case execute_stream(config, module, context, prompt, schema) do
        {:error, _} = error -> error
        stream -> {:ok, stream}
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

  defp execute_stream(config, module, context, prompt, schema) do
    metadata = telemetry_metadata(config, module, :stream)
    metadata = Map.put(metadata, :input, context.input)

    rendered_prompt =
      if prompt do
        case PromptRenderer.render(prompt, context.input, config) do
          {:ok, rendered} -> rendered
          {:error, _} -> nil
        end
      else
        nil
      end

    if rendered_prompt do
      emit_prompt_rendered(metadata, rendered_prompt)
    end

    _ctx = context_module().new(context.input, system_prompt: rendered_prompt)

    case LLMClient.stream_object(
           module,
           config.client,
           prompt,
           schema,
           config.client_opts,
           context,
           provider_override: config.provider
         ) do
      {:ok, stream_response} ->
        base_metadata = Map.put(metadata, :response, stream_response)

        :telemetry.execute([:ash_agent, :stream, :start], %{}, base_metadata)

        stream_response
        |> LLMClient.stream_to_tagged_chunks(config.output_type, config.provider)
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

  defp render_prompt(config, input) do
    case config.prompt do
      nil ->
        {:ok, nil}

      prompt ->
        PromptRenderer.render(prompt, input, config)
    end
  end

  defp build_schema(config) do
    case config.output_type do
      nil ->
        {:error, Error.schema_error("No output type configured", %{})}

      primitive when primitive in [:string, :integer, :float, :boolean] ->
        {:ok, nil}

      type_module ->
        schema = SchemaConverter.to_req_llm_schema(type_module)

        if is_list(schema) do
          {:ok, schema}
        else
          {:error,
           Error.schema_error("Invalid schema format", %{type: type_module, result: schema})}
        end
    end
  end

  defp telemetry_metadata(config, module, type) do
    %{
      agent: module,
      client: config.client,
      provider: config.provider,
      type: type,
      output_type: config.output_type
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

  defp handle_call_response({:ok, response}, config, metadata, ctx) do
    case LLMClient.parse_response(config.output_type, response) do
      {:ok, output} ->
        result = LLMClient.build_result(output, response, config.provider)
        enriched_metadata = build_call_metadata(metadata, {:ok, result}, response, ctx)
        {{:ok, result}, enriched_metadata}

      {:error, _} = error ->
        {error, Map.put(metadata, :context, ctx)}
    end
  end

  defp handle_call_response(error, _config, metadata, ctx) do
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

  defp context_module do
    AshAgent.RuntimeRegistry.get_context_module()
  end

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
