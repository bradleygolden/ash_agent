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
  Converts a ReqLLM response to an instance of the output TypedStruct.

  Returns `{:ok, struct}` with the built TypedStruct, or `{:error, reason}`.

  ## String Key Conversion

  When the response contains string keys, they are converted to atoms using
  `String.to_existing_atom/1`. This has important implications:

  - **If the atom exists**: The key is converted and included. If it's not a
    field in the struct, `Kernel.struct/2` silently ignores it.
  - **If the atom doesn't exist**: An `ArgumentError` is raised, caught, and
    returned as `{:error, %Error{type: :parse_error}}`.

  This means parsing behavior depends on which atoms exist in the VM at runtime.
  In tests, atoms defined in test modules may cause different behavior than in
  production. For deterministic testing of unknown key handling, use unique
  strings that are guaranteed not to exist as atoms (e.g., UUID-based keys).

  ## Examples

      # Successful parsing with known fields
      iex> parse_response(MyOutput, %{"name" => "test", "value" => 42})
      {:ok, %MyOutput{name: "test", value: 42}}

      # Extra fields are ignored when their atoms exist
      iex> parse_response(MyOutput, %{name: "test", extra: "ignored"})
      {:ok, %MyOutput{name: "test"}}

      # Unknown string keys cause errors if atom doesn't exist
      iex> parse_response(MyOutput, %{"nonexistent_key_abc123" => "value"})
      {:error, %Error{type: :parse_error}}

  """
  def parse_response(output_module, %_{} = response) do
    cond do
      response.__struct__ == output_module ->
        {:ok, response}

      match?(%ReqLLM.Response{}, response) ->
        case ReqLLM.Response.unwrap_object(response) do
          {:ok, object} when is_map(object) ->
            build_typed_struct(output_module, object)

          {:error, reason} ->
            {:error,
             Error.parse_error("ReqLLM response did not contain structured output", %{
               reason: reason
             })}
        end

      true ->
        struct_map = Map.from_struct(response)
        build_typed_struct(output_module, struct_map)
    end
  rescue
    e ->
      {:error,
       Error.parse_error("Failed to parse provider response", %{
         expected: output_module,
         response: response,
         exception: e
       })}
  end

  def parse_response(output_module, %{} = response) do
    build_typed_struct(output_module, response)
  end

  def parse_response(_output_module, nil) do
    {:error, Error.parse_error("Cannot parse nil response", %{response: nil})}
  end

  def parse_response(_output_module, response) when is_binary(response) do
    {:error, Error.parse_error("Cannot parse string response directly", %{response: response})}
  end

  def parse_response(output_module, %ReqLLM.Response{} = response) do
    object_data = ReqLLM.Response.object(response)
    build_typed_struct(output_module, object_data)
  end

  def parse_response(_output_module, response) do
    {:error, Error.parse_error("Unsupported response type", %{response: response})}
  end

  @doc """
  Converts a ReqLLM stream response to a stream of parsed objects.

  Returns an Enumerable that yields parsed TypedStruct instances.
  """
  def stream_to_structs(stream_response, output_module) do
    if enumerable_stream?(stream_response) do
      Stream.map(stream_response, &parse_stream_chunk(&1, output_module))
    else
      Stream.resource(
        fn -> stream_response end,
        &stream_next(&1, output_module),
        &stream_cleanup/1
      )
    end
  end

  defp parse_stream_chunk(chunk, output_module) do
    case parse_response(output_module, chunk) do
      {:ok, struct} -> struct
      {:error, _} -> chunk
    end
  end

  defp stream_next(response, output_module) do
    with {:ok, final_response} <- ReqLLM.StreamResponse.to_response(response),
         {:ok, struct} <- parse_response(output_module, final_response) do
      {[struct], :done}
    else
      _ -> {:halt, response}
    end
  end

  defp stream_cleanup(:done), do: :ok
  defp stream_cleanup(_), do: :ok

  defp enumerable_stream?(%Stream{}), do: true
  defp enumerable_stream?(stream) when is_function(stream, 2), do: true
  defp enumerable_stream?(_), do: false

  defp merge_client_opts(opts) do
    test_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Keyword.merge(opts, test_opts)
  end

  defp build_typed_struct(module, data) when is_map(data) do
    atom_data =
      for {k, v} <- data, into: %{} do
        key = if is_binary(k), do: String.to_existing_atom(k), else: k
        {key, v}
      end

    struct = struct(module, atom_data)
    {:ok, struct}
  rescue
    e ->
      {:error,
       Error.parse_error("Failed to build struct from LLM response", %{
         module: module,
         data: data,
         exception: e
       })}
  end

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

  def response_usage(%StreamResponse{} = response) do
    StreamResponse.usage(response)
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
end
