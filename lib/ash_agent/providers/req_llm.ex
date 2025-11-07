defmodule AshAgent.Providers.ReqLLM do
  @moduledoc """
  Provider implementation for ReqLLM library.

  Wraps the existing ReqLLM integration to conform to the
  AshAgent.Provider behavior. Preserves all existing functionality
  including retry logic.

  ## Configuration

      agent do
        provider :req_llm,
          client: "anthropic:claude-3-5-sonnet",
          temperature: 0.7,
          max_tokens: 4096
      end

  ## Features

  - Synchronous and streaming calls
  - Automatic retry with exponential backoff
  - Structured output via JSON schema
  - Multiple model support (Anthropic, OpenAI, etc.)
  """

  @behaviour AshAgent.Provider

  require Logger

  @impl true
  def call(client, prompt, schema, opts, _context) do
    max_attempts = Keyword.get(opts, :max_retries, 3)
    base_delay_ms = Keyword.get(opts, :retry_base_delay_ms, 100)

    with_retry(
      fn -> ReqLLM.generate_object(client, prompt, schema, opts) end,
      max_attempts,
      base_delay_ms
    )
  end

  @impl true
  def stream(client, prompt, schema, opts, _context) do
    ReqLLM.stream_object(client, prompt, schema, opts)
  end

  @impl true
  def introspect do
    %{
      provider: :req_llm,
      features: [
        :sync_call,
        :streaming,
        :structured_output,
        :function_calling,
        :tool_calling,
        :auto_retry
      ],
      models: available_models()
    }
  end

  defp with_retry(func, attempts_left, base_delay_ms, attempt_num \\ 1)

  defp with_retry(_func, 0, _base_delay_ms, attempt_num) do
    Logger.error("ReqLLM provider: All retry attempts exhausted (#{attempt_num - 1} attempts)")
    {:error, :max_retries_exceeded}
  end

  defp with_retry(func, attempts_left, base_delay_ms, attempt_num) do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} = error ->
        if retryable?(reason) and attempts_left > 1 do
          delay = calculate_delay(base_delay_ms, attempt_num)

          Logger.warning(
            "ReqLLM provider: Retryable error on attempt #{attempt_num}, " <>
              "retrying in #{delay}ms. Reason: #{inspect(reason)}"
          )

          Process.sleep(delay)
          with_retry(func, attempts_left - 1, base_delay_ms, attempt_num + 1)
        else
          Logger.error(
            "ReqLLM provider: Non-retryable error or max attempts reached. " <>
              "Reason: #{inspect(reason)}"
          )

          error
        end
    end
  end

  defp calculate_delay(base_delay_ms, attempt_num) do
    exponential_delay = base_delay_ms * :math.pow(2, attempt_num - 1)
    jitter = :rand.uniform(round(exponential_delay * 0.1))
    round(exponential_delay + jitter)
  end

  defp retryable?(reason) do
    case reason do
      %{status: status} when status in [429, 500, 502, 503, 504] -> true
      :timeout -> true
      :econnrefused -> true
      _ -> false
    end
  end

  defp available_models do
    [
      "anthropic:claude-3-5-sonnet",
      "anthropic:claude-3-opus",
      "anthropic:claude-3-haiku",
      "openai:gpt-4",
      "openai:gpt-4-turbo",
      "openai:gpt-3.5-turbo"
    ]
  end
end
