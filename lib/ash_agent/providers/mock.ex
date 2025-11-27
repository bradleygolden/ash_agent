defmodule AshAgent.Providers.Mock do
  @moduledoc """
  Mock provider for testing without API calls.

  ## Usage

      agent do
        provider :mock,
          mock_response: %{"status" => "success"},
          mock_chunks: [%{"delta" => "Hello"}, %{"delta" => " world"}]
      end

  ## Use Cases

  - Unit testing AshAgent features without hitting APIs
  - Development and prototyping
  - Example code and documentation
  - CI/CD pipelines (fast, no API costs)
  """

  @behaviour AshAgent.Provider

  @impl true
  def call(_client, _prompt, _schema, opts, _context, _tools, _messages) do
    response = Keyword.get(opts, :mock_response, default_response())

    if delay = Keyword.get(opts, :mock_delay_ms) do
      Process.sleep(delay)
    end

    {:ok, response}
  end

  @impl true
  def stream(_client, _prompt, _schema, opts, _context, _tools, _messages) do
    chunks = Keyword.get(opts, :mock_chunks, default_chunks())

    stream =
      Stream.map(chunks, fn chunk ->
        if delay = Keyword.get(opts, :mock_chunk_delay_ms) do
          Process.sleep(delay)
        end

        chunk
      end)

    {:ok, stream}
  end

  @impl true
  def introspect do
    %{
      provider: :mock,
      features: [:sync_call, :streaming, :configurable_responses, :tool_calling],
      models: ["mock:test"],
      constraints: %{max_tokens: :unlimited}
    }
  end

  @impl true
  def extract_thinking(%{thinking: thinking}) when is_binary(thinking), do: thinking
  def extract_thinking(_response), do: nil

  defp default_response do
    %{"message" => "This is a mock response"}
  end

  defp default_chunks do
    [
      %{"delta" => "Mock "},
      %{"delta" => "streaming "},
      %{"delta" => "response"}
    ]
  end
end
