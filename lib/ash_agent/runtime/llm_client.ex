defmodule AshAgent.Runtime.LLMClient do
  @moduledoc """
  LLM client interface for AshAgent.

  Handles all interactions with the LLM via ReqLLM, including:
  - Generating structured objects
  - Streaming structured objects
  - Building client options
  - Parsing responses into TypedStruct instances
  """

  alias AshAgent.Error

  @doc """
  Generates a structured object from the LLM.

  Returns `{:ok, response}` with the raw ReqLLM response, or `{:error, reason}`.
  """
  def generate_object(client, prompt, schema, opts \\ []) do
    opts = merge_client_opts(opts)

    retry_with_backoff(fn ->
      ReqLLM.generate_object(client, prompt, schema, opts)
    end)
  rescue
    e ->
      {:error,
       Error.llm_error("LLM generation failed", %{
         client: client,
         exception: e
       })}
  end

  @doc """
  Streams a structured object from the LLM.

  Returns `{:ok, stream}` with the ReqLLM stream response, or `{:error, reason}`.
  """
  def stream_object(client, prompt, schema, opts \\ []) do
    opts = merge_client_opts(opts)
    ReqLLM.stream_object(client, prompt, schema, opts)
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
  def parse_response(output_module, response) do
    object_data = ReqLLM.Response.object(response)
    build_typed_struct(output_module, object_data)
  end

  @doc """
  Converts a ReqLLM stream response to a stream of parsed objects.

  Returns an Enumerable that yields parsed TypedStruct instances.
  """
  def stream_to_structs(stream_response, output_module) do
    Stream.resource(
      fn -> stream_response end,
      &stream_next(&1, output_module),
      &stream_cleanup/1
    )
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

  defp retry_with_backoff(fun, max_attempts \\ 3, base_delay \\ 100) do
    do_retry(fun, max_attempts, base_delay, 1)
  end

  defp do_retry(fun, max_attempts, base_delay, attempt) do
    case fun.() do
      {:ok, _} = success ->
        success

      {:error, _reason} when attempt < max_attempts ->
        delay = (base_delay * :math.pow(2, attempt - 1)) |> round()
        Process.sleep(delay)
        do_retry(fun, max_attempts, base_delay, attempt + 1)

      {:error, _} = error ->
        error
    end
  end
end
