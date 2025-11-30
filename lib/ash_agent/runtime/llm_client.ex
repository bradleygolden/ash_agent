defmodule AshAgent.Runtime.LLMClient do
  @moduledoc """
  LLM client adapter that delegates to configured providers.

  This module no longer calls LLM APIs directly. Instead, it:
  1. Resolves the provider module from agent configuration
  2. Delegates calls to the provider
  3. Handles provider-agnostic concerns (error wrapping, response parsing)

  ## Provider Resolution

  Providers are resolved from the agent's DSL configuration.
  The provider can be an atom preset (`:req_llm`, `:mock`) or a custom module.

  ## Public Extension API

  This module is part of AshAgent's **public extension API**. It is intended to be
  used by extension packages like `ash_agent_tools` to execute LLM calls.

  **Stability**: This module's public functions have stability guarantees. Breaking
  changes will follow semantic versioning (major version bump).

  **Public Functions**:
  - `generate_object/7` - Execute synchronous LLM call
  - `stream_object/7` - Execute streaming LLM call
  """

  alias AshAgent.Error
  alias AshAgent.ProviderRegistry
  alias AshAgent.Result
  alias ReqLLM.StreamResponse
  require Logger

  @doc """
  Generates a structured object from the LLM via the configured provider.

  Returns `{:ok, response}` with the provider response, or `{:error, reason}`.
  """
  def generate_object(resource, client, prompt, schema, opts \\ [], context, options \\ []) do
    provider_override = Keyword.get(options, :provider_override)
    tools = Keyword.get(options, :tools)
    messages = Keyword.get(options, :messages)

    with {:ok, provider} <- resolve_provider(resource, provider_override) do
      opts = merge_client_opts(opts)

      Logger.debug("LLMClient: Calling provider #{inspect(provider)}")

      case provider.call(client, prompt, schema, opts, context, tools, messages) do
        {:ok, response} ->
          {:ok, response}

        {:error, reason} ->
          {:error,
           Error.llm_error("Provider #{inspect(provider)} call failed: #{inspect(reason)}")}
      end
    end
  rescue
    e ->
      {:error,
       Error.llm_error("LLM generation failed", %{
         client: client,
         exception: e
       })}
  end

  @doc """
  Generates a structured object using separate system prompt and messages.

  This is the context-based API that receives pre-formatted messages.
  Returns `{:ok, response}` with the provider response, or `{:error, reason}`.
  """
  def generate_object_with_messages(
        resource,
        client,
        system_prompt,
        messages,
        schema,
        opts,
        options \\ []
      ) do
    provider_override = Keyword.get(options, :provider_override)
    tools = Keyword.get(options, :tools)
    context = Keyword.get(options, :context)

    with {:ok, provider} <- resolve_provider(resource, provider_override) do
      opts =
        opts
        |> merge_client_opts()
        |> Keyword.put(:system_prompt, system_prompt)

      Logger.debug("LLMClient: Calling provider #{inspect(provider)} with messages")

      case provider.call(client, nil, schema, opts, context, tools, messages) do
        {:ok, response} ->
          {:ok, response}

        {:error, reason} ->
          {:error,
           Error.llm_error("Provider #{inspect(provider)} call failed: #{inspect(reason)}")}
      end
    end
  rescue
    e ->
      {:error,
       Error.llm_error("LLM generation failed", %{
         client: client,
         exception: e
       })}
  end

  @doc """
  Streams a structured object using separate system prompt and messages.

  This is the context-based API that receives pre-formatted messages.
  Returns `{:ok, stream}` with the provider stream response, or `{:error, reason}`.
  """
  def stream_object_with_messages(
        resource,
        client,
        system_prompt,
        messages,
        schema,
        opts,
        options \\ []
      ) do
    provider_override = Keyword.get(options, :provider_override)
    tools = Keyword.get(options, :tools)
    context = Keyword.get(options, :context)

    with {:ok, provider} <- resolve_provider(resource, provider_override) do
      opts =
        opts
        |> merge_client_opts()
        |> Keyword.put(:system_prompt, system_prompt)

      Logger.debug("LLMClient: Streaming via provider #{inspect(provider)} with messages")

      case provider.stream(client, nil, schema, opts, context, tools, messages) do
        {:ok, stream} ->
          {:ok, stream}

        {:error, reason} ->
          {:error,
           Error.llm_error("Provider #{inspect(provider)} stream failed: #{inspect(reason)}")}
      end
    end
  rescue
    e ->
      {:error,
       Error.llm_error("LLM streaming failed", %{
         client: client,
         exception: e
       })}
  end

  @doc """
  Streams a structured object from the LLM via the configured provider.

  Returns `{:ok, stream}` with the provider stream response, or `{:error, reason}`.
  """
  def stream_object(resource, client, prompt, schema, opts \\ [], context, options \\ []) do
    provider_override = Keyword.get(options, :provider_override)
    tools = Keyword.get(options, :tools)
    messages = Keyword.get(options, :messages)

    with {:ok, provider} <- resolve_provider(resource, provider_override) do
      opts = merge_client_opts(opts)

      Logger.debug("LLMClient: Streaming via provider #{inspect(provider)}")

      case provider.stream(client, prompt, schema, opts, context, tools, messages) do
        {:ok, stream} ->
          {:ok, stream}

        {:error, reason} ->
          {:error,
           Error.llm_error("Provider #{inspect(provider)} stream failed: #{inspect(reason)}")}
      end
    end
  rescue
    e ->
      {:error,
       Error.llm_error("LLM streaming failed", %{
         client: client,
         exception: e
       })}
  end

  @doc """
  Validates and parses an LLM response using a Zoi schema.

  Returns `{:ok, validated_data}` with the parsed result, or `{:error, reason}`.

  ## Zoi Schema Validation

  Responses are validated and coerced using Zoi schemas. When using schemas
  with `coerce: true`, string keys from LLM responses are automatically
  converted to atoms and validated against the schema.

  ## Examples

      # Successful parsing with Zoi schema
      schema = Zoi.object(%{name: Zoi.string(), value: Zoi.integer()}, coerce: true)
      iex> parse_response(schema, %{"name" => "test", "value" => 42})
      {:ok, %{name: "test", value: 42}}

      # Schema with struct conversion
      schema = Zoi.object(%{content: Zoi.string()}, coerce: true) |> Zoi.to_struct(Reply)
      iex> parse_response(schema, %{"content" => "Hello"})
      {:ok, %Reply{content: "Hello"}}

  """
  def parse_response(output_type, response)
      when output_type in [:string, :integer, :float, :boolean] do
    case extract_text(response) do
      nil -> {:error, Error.parse_error("No text content in response", %{response: response})}
      text -> parse_primitive(output_type, text)
    end
  end

  def parse_response(output_schema, %_{} = response) do
    cond do
      match?(%ReqLLM.Response{}, response) ->
        case ReqLLM.Response.unwrap_object(response) do
          {:ok, object} when is_map(object) ->
            parse_with_zoi(output_schema, object)

          {:error, reason} ->
            {:error,
             Error.parse_error("ReqLLM response did not contain structured output", %{
               reason: reason
             })}
        end

      match?(%AshBaml.Response{}, response) ->
        parse_response(output_schema, AshBaml.Response.unwrap(response))

      true ->
        struct_map = Map.from_struct(response)
        parse_with_zoi(output_schema, struct_map)
    end
  rescue
    e ->
      {:error,
       Error.parse_error("Failed to parse provider response", %{
         expected: output_schema,
         response: response,
         exception: e
       })}
  end

  def parse_response(output_schema, %{} = response) do
    parse_with_zoi(output_schema, response)
  end

  def parse_response(_output_schema, nil) do
    {:error, Error.parse_error("Cannot parse nil response", %{response: nil})}
  end

  def parse_response(output_type, response)
      when output_type in [:string, :integer, :float, :boolean] and is_binary(response) do
    parse_response(output_type, %{text: response})
  end

  def parse_response(_output_schema, response) when is_binary(response) do
    {:error, Error.parse_error("Cannot parse string response directly", %{response: response})}
  end

  def parse_response(output_schema, %ReqLLM.Response{} = response) do
    object_data = ReqLLM.Response.object(response)
    parse_with_zoi(output_schema, object_data)
  end

  def parse_response(_output_schema, response) do
    {:error, Error.parse_error("Unsupported response type", %{response: response})}
  end

  @doc """
  Converts a ReqLLM stream response to a stream of parsed objects.

  Returns an Enumerable that yields validated data using the Zoi schema.
  """
  def stream_to_structs(stream_response, output_schema) do
    if enumerable_stream?(stream_response) do
      Stream.map(stream_response, &parse_stream_chunk(&1, output_schema))
    else
      Stream.resource(
        fn -> stream_response end,
        &stream_next(&1, output_schema),
        &stream_cleanup/1
      )
    end
  end

  @doc """
  Converts a stream response to tagged chunks for rich streaming.

  Returns an Enumerable that yields tagged tuples:
  - `{:thinking, text}` - thinking/reasoning content chunks
  - `{:content, data}` - parsed content chunks validated by Zoi schema
  - `{:done, result}` - final Result struct with full metadata

  ## Example

      {:ok, stream} = AshAgent.Runtime.stream(MyAgent, input: "Hello")
      Enum.each(stream, fn
        {:thinking, text} -> IO.puts("Thinking: \#{text}")
        {:content, data} -> IO.puts("Content: \#{inspect(data)}")
        {:done, result} -> IO.puts("Done! Final: \#{inspect(result.output)}")
      end)

  """
  def stream_to_tagged_chunks(stream_response, output_schema, provider) do
    actual_stream = extract_enumerable_stream(stream_response)

    if actual_stream do
      state_ref = make_ref()
      Process.put({__MODULE__, state_ref}, {nil, nil})

      tagged_stream =
        actual_stream
        |> Stream.flat_map(&tag_chunk(&1, output_schema))
        |> Stream.map(fn chunk ->
          {last_content, accumulated_thinking} = Process.get({__MODULE__, state_ref}, {nil, nil})
          accumulate_chunk(state_ref, chunk, last_content, accumulated_thinking)
          chunk
        end)

      done_stream =
        Stream.resource(
          fn -> nil end,
          fn
            nil ->
              {last_content, accumulated_thinking} =
                Process.get({__MODULE__, state_ref}, {nil, nil})

              Process.delete({__MODULE__, state_ref})
              finalize_tagged_stream_result(last_content, accumulated_thinking, stream_response)

            :done ->
              {:halt, :done}
          end,
          fn _ -> :ok end
        )

      Stream.concat(tagged_stream, done_stream)
    else
      state_ref = make_ref()
      Process.put({__MODULE__, state_ref}, {nil, nil})

      content_stream =
        stream_response
        |> stream_to_structs(output_schema)
        |> Stream.map(fn chunk ->
          Process.put({__MODULE__, state_ref}, {chunk, nil})
          {:content, chunk}
        end)

      done_stream =
        Stream.resource(
          fn -> nil end,
          fn
            nil ->
              {last_content, _thinking} = Process.get({__MODULE__, state_ref}, {nil, nil})
              Process.delete({__MODULE__, state_ref})
              finalize_stream_result(last_content, stream_response, provider)

            :done ->
              {:halt, :done}
          end,
          fn _ -> :ok end
        )

      Stream.concat(content_stream, done_stream)
    end
  end

  defp parse_primitive(:string, text), do: {:ok, text}

  defp parse_primitive(:integer, text) do
    case Integer.parse(String.trim(text)) do
      {int, _} -> {:ok, int}
      :error -> {:error, Error.parse_error("Cannot parse as integer", %{text: text})}
    end
  end

  defp parse_primitive(:float, text) do
    case Float.parse(String.trim(text)) do
      {float, _} -> {:ok, float}
      :error -> {:error, Error.parse_error("Cannot parse as float", %{text: text})}
    end
  end

  defp parse_primitive(:boolean, text) do
    case String.trim(String.downcase(text)) do
      t when t in ["true", "yes", "1"] -> {:ok, true}
      f when f in ["false", "no", "0"] -> {:ok, false}
      _ -> {:error, Error.parse_error("Cannot parse as boolean", %{text: text})}
    end
  end

  defp accumulate_chunk(state_ref, {:thinking, text}, last_content, accumulated_thinking) do
    new_thinking = (accumulated_thinking || "") <> text
    Process.put({__MODULE__, state_ref}, {last_content, new_thinking})
  end

  defp accumulate_chunk(state_ref, {:content, struct}, _last_content, accumulated_thinking) do
    Process.put({__MODULE__, state_ref}, {struct, accumulated_thinking})
  end

  defp accumulate_chunk(_state_ref, _chunk, _last_content, _accumulated_thinking), do: :ok

  defp finalize_tagged_stream_result(nil, _thinking, _stream_response), do: {:halt, :done}

  defp finalize_tagged_stream_result(last_content, accumulated_thinking, stream_response) do
    result = %Result{
      output: last_content,
      thinking: accumulated_thinking,
      usage: nil,
      model: nil,
      finish_reason: nil,
      raw_response: stream_response
    }

    {[{:done, result}], :done}
  end

  defp finalize_stream_result(nil, _stream_response, _provider), do: {:halt, :done}

  defp finalize_stream_result(last_content, stream_response, provider) do
    result = build_result(last_content, stream_response, provider)
    {[{:done, result}], :done}
  end

  defp tag_chunk(%ReqLLM.StreamChunk{type: :thinking} = chunk, _output_schema) do
    thinking_text = Map.get(chunk, :text) || Map.get(chunk, :thinking, "")
    [{:thinking, thinking_text}]
  end

  defp tag_chunk(%ReqLLM.StreamChunk{type: :content} = chunk, output_schema) do
    case parse_response(output_schema, chunk) do
      {:ok, data} -> [{:content, data}]
      {:error, _} -> [{:content, chunk}]
    end
  end

  defp tag_chunk(%ReqLLM.StreamChunk{type: :meta}, _output_schema), do: []

  defp tag_chunk(%ReqLLM.StreamChunk{type: :tool_call} = chunk, _output_schema),
    do: [{:tool_call, chunk}]

  defp tag_chunk(chunk, output_schema) do
    case parse_response(output_schema, chunk) do
      {:ok, data} -> [{:content, data}]
      {:error, _} -> [{:content, chunk}]
    end
  end

  defp parse_stream_chunk(chunk, output_schema) do
    case parse_response(output_schema, chunk) do
      {:ok, data} -> data
      {:error, _} -> chunk
    end
  end

  defp stream_next(:done, _output_schema), do: {:halt, :done}

  defp stream_next(response, output_schema) do
    with {:ok, final_response} <- ReqLLM.StreamResponse.to_response(response),
         {:ok, data} <- parse_response(output_schema, final_response) do
      {[data], :done}
    else
      _ -> {:halt, response}
    end
  end

  defp stream_cleanup(:done), do: :ok
  defp stream_cleanup(_), do: :ok

  defp enumerable_stream?(%Stream{}), do: true
  defp enumerable_stream?(stream) when is_function(stream, 2), do: true
  defp enumerable_stream?(_), do: false

  defp extract_enumerable_stream(%StreamResponse{stream: stream}) when not is_nil(stream),
    do: stream

  defp extract_enumerable_stream(%Stream{} = stream), do: stream
  defp extract_enumerable_stream(stream) when is_function(stream, 2), do: stream
  defp extract_enumerable_stream(_), do: nil

  defp merge_client_opts(opts) do
    test_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Keyword.merge(opts, test_opts)
  end

  defp parse_with_zoi(schema, data) when is_map(data) do
    case Zoi.parse(schema, data) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, errors} ->
        {:error,
         Error.parse_error("Zoi validation failed", %{
           schema: schema,
           data: data,
           errors: errors
         })}
    end
  rescue
    e ->
      {:error,
       Error.parse_error("Failed to parse with Zoi schema", %{
         schema: schema,
         data: data,
         exception: e
       })}
  end

  defp extract_text(%ReqLLM.Response{} = response), do: ReqLLM.Response.text(response)

  defp extract_text(%AshBaml.Response{} = response),
    do: extract_text(AshBaml.Response.unwrap(response))

  defp extract_text(%{text: text}) when is_binary(text), do: text
  defp extract_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(_), do: nil

  defp resolve_provider(resource, override) do
    case override do
      nil ->
        resource
        |> AshAgent.Info.provider()
        |> ProviderRegistry.resolve()

      other ->
        ProviderRegistry.resolve(other)
    end
  end

  @doc """
  Extracts provider usage metadata from a response or stream response, if available.
  """
  @spec response_usage(atom() | module() | nil, term()) :: map() | nil
  def response_usage(provider, response) do
    case provider_usage(provider, response) do
      nil -> response_usage(response)
      usage -> usage
    end
  end

  @spec response_usage(term()) :: map() | nil
  def response_usage(%ReqLLM.Response{} = response) do
    ReqLLM.Response.usage(response)
  end

  def response_usage(%StreamResponse{}) do
    nil
  end

  def response_usage(%module{} = response) do
    if function_exported?(module, :usage, 1) do
      module.usage(response)
    else
      nil
    end
  end

  def response_usage(_), do: nil

  defp provider_usage(provider, response) when provider in [:baml, AshAgent.Providers.Baml] do
    map_usage(response)
  end

  defp provider_usage(_provider, _response), do: nil

  defp map_usage(%{usage: usage}) when is_map(usage), do: usage
  defp map_usage(%{"usage" => usage}) when is_map(usage), do: usage
  defp map_usage(_), do: nil

  @doc """
  Builds an AshAgent.Result from a parsed output and provider response.

  Extracts thinking, usage, model, and finish_reason from the provider response
  and wraps everything in a Result struct.

  ## Parameters

  - `output` - The parsed output struct
  - `provider_response` - The raw response from the provider
  - `provider` - The provider module or atom

  ## Returns

  An `%AshAgent.Result{}` struct with the output and extracted metadata.
  """
  def build_result(output, provider_response, provider) do
    %Result{
      output: output,
      thinking: extract_thinking_from_provider(provider, provider_response),
      usage: response_usage(provider, provider_response),
      model: extract_model(provider_response),
      finish_reason: extract_finish_reason(provider_response),
      raw_response: provider_response
    }
  end

  @doc """
  Extracts thinking content from a provider response using the provider's callback.

  Falls back to default extraction logic if the provider returns `:default`.
  """
  def extract_thinking_from_provider(provider, response) do
    provider_module = resolve_provider_module(provider)

    if provider_module && function_exported?(provider_module, :extract_thinking, 1) do
      case provider_module.extract_thinking(response) do
        :default -> default_extract_thinking(response)
        thinking -> thinking
      end
    else
      default_extract_thinking(response)
    end
  end

  defp default_extract_thinking(%ReqLLM.Response{} = response) do
    case ReqLLM.Response.thinking(response) do
      "" -> nil
      nil -> nil
      text -> text
    end
  end

  defp default_extract_thinking(%{thinking: thinking}) when is_binary(thinking), do: thinking
  defp default_extract_thinking(%{"thinking" => thinking}) when is_binary(thinking), do: thinking
  defp default_extract_thinking(_), do: nil

  defp extract_model(%ReqLLM.Response{model: model}) when is_binary(model), do: model
  defp extract_model(%ReqLLM.Response{}), do: nil
  defp extract_model(%{model: model}) when is_binary(model), do: model
  defp extract_model(%{"model" => model}) when is_binary(model), do: model
  defp extract_model(_), do: nil

  defp extract_finish_reason(%ReqLLM.Response{} = response) do
    ReqLLM.Response.finish_reason(response)
  end

  defp extract_finish_reason(%{finish_reason: reason}) when is_atom(reason), do: reason

  defp extract_finish_reason(%{finish_reason: reason}) when is_binary(reason),
    do: String.to_atom(reason)

  defp extract_finish_reason(%{"finish_reason" => reason}) when is_binary(reason),
    do: String.to_atom(reason)

  defp extract_finish_reason(_), do: nil

  defp resolve_provider_module(provider) when is_atom(provider) do
    case ProviderRegistry.resolve(provider) do
      {:ok, module} -> module
      _ -> nil
    end
  end

  defp resolve_provider_module(_), do: nil
end
