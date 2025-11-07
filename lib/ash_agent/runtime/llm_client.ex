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
  """

  alias AshAgent.Error
  alias AshAgent.ProviderRegistry
  alias ReqLLM.StreamResponse
  require Logger

  @doc """
  Generates a structured object from the LLM via the configured provider.

  Returns `{:ok, response}` with the provider response, or `{:error, reason}`.
  """
  def generate_object(resource, client, prompt, schema, opts \\ [], context, tools \\ nil, messages \\ nil) do
    with {:ok, provider} <- resolve_provider(resource) do
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
  def stream_object(resource, client, prompt, schema, opts \\ [], context, tools \\ nil, messages \\ nil) do
    with {:ok, provider} <- resolve_provider(resource) do
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
        build_typed_struct(output_module, Map.from_struct(response))
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

  def parse_response(output_module, response) do
    object_data = ReqLLM.Response.object(response)
    build_typed_struct(output_module, object_data)
  end

  @doc """
  Converts a ReqLLM stream response to a stream of parsed objects.

  Returns an Enumerable that yields parsed TypedStruct instances.
  """
  def stream_to_structs(stream_response, output_module) do
    cond do
      enumerable_stream?(stream_response) ->
        Stream.map(stream_response, fn chunk ->
          case parse_response(output_module, chunk) do
            {:ok, struct} -> struct
            {:error, _} -> chunk
          end
        end)

      true ->
        Stream.resource(
          fn -> stream_response end,
          &stream_next(&1, output_module),
          &stream_cleanup/1
        )
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

  defp resolve_provider(resource) do
    resource
    |> AshAgent.Info.provider()
    |> ProviderRegistry.resolve()
  end

  @doc """
  Extracts provider usage metadata from a response or stream response, if available.
  """
  @spec response_usage(term()) :: map() | nil
  def response_usage(%ReqLLM.Response{} = response) do
    ReqLLM.Response.usage(response)
  end

  def response_usage(%StreamResponse{} = response) do
    StreamResponse.usage(response)
  end

  def response_usage(%{usage: usage}) when is_map(usage), do: usage
  def response_usage(%{"usage" => usage}) when is_map(usage), do: usage

  def response_usage(%module{} = response) do
    cond do
      function_exported?(module, :usage, 1) ->
        module.usage(response)

      true ->
        nil
    end
  end

  def response_usage(_), do: nil
end
