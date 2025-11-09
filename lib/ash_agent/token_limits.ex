defmodule AshAgent.TokenLimits do
  @moduledoc """
  Manages token limits and warnings for AshAgent providers.
  """

  @default_limits %{
    "anthropic:claude-3-5-sonnet" => 200_000,
    "anthropic:claude-3-opus" => 200_000,
    "anthropic:claude-3-sonnet" => 200_000,
    "anthropic:claude-3-haiku" => 200_000,
    "openai:gpt-4" => 128_000,
    "openai:gpt-4-turbo" => 128_000,
    "openai:gpt-3.5-turbo" => 16_385
  }

  @default_warning_threshold 0.8

  @doc """
  Gets the token limit for a given provider/model combination.

  Returns the configured limit from application config if available,
  otherwise falls back to default limits.
  """
  @spec get_limit(String.t()) :: non_neg_integer() | nil
  def get_limit(client) when is_binary(client) do
    custom_limits = Application.get_env(:ash_agent, :token_limits, %{})

    Map.get(custom_limits, client) || Map.get(@default_limits, client)
  end

  @doc """
  Gets the warning threshold percentage.

  Returns the configured threshold from application config if available,
  otherwise falls back to default (0.8 = 80%).
  """
  @spec get_warning_threshold() :: float()
  def get_warning_threshold do
    Application.get_env(:ash_agent, :token_warning_threshold, @default_warning_threshold)
  end

  @doc """
  Checks if cumulative tokens have exceeded the warning threshold.

  Returns `{:warn, limit, threshold}` if threshold exceeded,
  or `:ok` otherwise.
  """
  @spec check_limit(non_neg_integer(), String.t()) ::
          :ok | {:warn, non_neg_integer(), float()}
  def check_limit(cumulative_tokens, client) when is_integer(cumulative_tokens) do
    case get_limit(client) do
      nil ->
        :ok

      limit ->
        threshold = get_warning_threshold()
        threshold_tokens = trunc(limit * threshold)

        if cumulative_tokens >= threshold_tokens do
          {:warn, limit, threshold}
        else
          :ok
        end
    end
  end
end
