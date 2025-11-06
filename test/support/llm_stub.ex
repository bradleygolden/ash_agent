defmodule AshAgent.Test.LLMStub do
  @moduledoc """
  Helper for stubbing LLM responses in tests using Req.Test.

  This module provides convenient functions to create Req.Test stubs
  that mimic LLM API responses for testing AshAgent functionality.

  ## Usage

      # In your test
      Req.Test.stub(AshAgent.LLMStub, LLMStub.object_response(%{
        "content" => "Hello from test!",
        "confidence" => 0.95
      }))

      {:ok, result} = MyAgent.call(%{})
  """

  @doc """
  Creates a stub for a successful structured object response.

  This is the most common stub for AshAgent tests, as agents typically
  return structured data that maps to TypedStruct modules.

  ## Parameters

    * `object_data` - A map containing the object fields that will be
      returned by the LLM and parsed into the agent's output TypedStruct.

  ## Examples

      iex> stub = LLMStub.object_response(%{
      ...>   "content" => "Hello!",
      ...>   "confidence" => 0.95
      ...> })
      iex> is_function(stub, 1)
      true

  """
  @spec object_response(map()) :: (Plug.Conn.t() -> Plug.Conn.t())
  def object_response(object_data) when is_map(object_data) do
    fn conn ->
      string_key_data = atomize_keys_to_strings(object_data)

      Req.Test.json(conn, %{
        "id" => "msg_#{:rand.uniform(1000)}",
        "type" => "message",
        "role" => "assistant",
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu_#{:rand.uniform(1000)}",
            "name" => "structured_output",
            "input" => string_key_data
          }
        ],
        "model" => "claude-3-5-sonnet-20241022",
        "stop_reason" => "tool_use",
        "usage" => %{
          "input_tokens" => 10,
          "output_tokens" => 20
        }
      })
    end
  end

  defp atomize_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, atomize_keys_to_strings(v)}
    end)
  end

  defp atomize_keys_to_strings(value), do: value

  @doc """
  Simulates an API error response.

  Use this to test error handling in your agents.

  ## Parameters

    * `status` - HTTP status code (default: 500)
    * `message` - Error message (default: "Internal server error")

  ## Examples

      iex> stub = LLMStub.error_response(429, "Rate limit exceeded")
      iex> is_function(stub, 1)
      true

  """
  @spec error_response(integer(), String.t()) :: (Plug.Conn.t() -> Plug.Conn.t())
  def error_response(status \\ 500, message \\ "Internal server error") do
    fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{
        "error" => %{
          "type" => "api_error",
          "message" => message
        }
      })
    end
  end

  @doc """
  Simulates a network timeout error.

  Use this to test timeout handling in your agents.

  ## Examples

      iex> stub = LLMStub.timeout_error()
      iex> is_function(stub, 1)
      true

  """
  @spec timeout_error() :: (Plug.Conn.t() -> Plug.Conn.t())
  def timeout_error do
    fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end
  end

  @doc """
  Simulates a connection refused error.

  Use this to test network error handling.

  ## Examples

      iex> stub = LLMStub.connection_refused()
      iex> is_function(stub, 1)
      true

  """
  @spec connection_refused() :: (Plug.Conn.t() -> Plug.Conn.t())
  def connection_refused do
    fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end
  end
end
