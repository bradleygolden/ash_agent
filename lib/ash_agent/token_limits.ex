defmodule AshAgent.TokenLimits do
  @moduledoc """
  Manages token limits and warnings for AshAgent providers.

  Token limits must be configured via application config:

      config :ash_agent, :token_limits, %{
        "anthropic:claude-3-5-sonnet" => 200_000,
        "openai:gpt-4" => 128_000
      }

  For testing, configuration can be passed directly as optional parameters
  to avoid mutating application environment.
  """

  @default_warning_threshold 0.8

  @doc """
  Gets the token limit for a given provider/model combination.

  Returns the configured limit from application config, or nil if not configured.

  ## Parameters
    - `client` - The client identifier (e.g., "anthropic:claude-3-5-sonnet")
    - `limits` - Optional limits map. If provided, uses this instead of application config.

  ## Examples

      iex> TokenLimits.get_limit("anthropic:claude-3-5-sonnet")
      200_000

      iex> TokenLimits.get_limit("anthropic:claude-3-5-sonnet", %{"anthropic:claude-3-5-sonnet" => 100_000})
      100_000
  """
  @spec get_limit(String.t(), map() | nil) :: non_neg_integer() | nil
  def get_limit(client, limits \\ nil) when is_binary(client) do
    limits = limits || Application.get_env(:ash_agent, :token_limits, %{})
    Map.get(limits, client)
  end

  @doc """
  Gets the warning threshold percentage.

  Returns the configured threshold from application config if available,
  otherwise falls back to default (0.8 = 80%).

  ## Parameters
    - `threshold` - Optional threshold value. If provided, uses this instead of application config.

  ## Examples

      iex> TokenLimits.get_warning_threshold()
      0.8

      iex> TokenLimits.get_warning_threshold(0.9)
      0.9
  """
  @spec get_warning_threshold(float() | nil) :: float()
  def get_warning_threshold(threshold \\ nil) do
    threshold ||
      Application.get_env(:ash_agent, :token_warning_threshold, @default_warning_threshold)
  end

  @doc """
  Checks if cumulative tokens have exceeded the warning threshold.

  Returns `{:warn, limit, threshold}` if threshold exceeded,
  or `:ok` otherwise.

  ## Parameters
    - `cumulative_tokens` - The cumulative token count
    - `client` - The client identifier
    - `limits` - Optional limits map. If provided, uses this instead of application config.
    - `threshold` - Optional threshold value. If provided, uses this instead of application config.

  ## Examples

      iex> TokenLimits.check_limit(100_000, "anthropic:claude-3-5-sonnet")
      :ok

      iex> TokenLimits.check_limit(180_000, "anthropic:claude-3-5-sonnet")
      {:warn, 200_000, 0.8}
  """
  @spec check_limit(non_neg_integer(), String.t(), map() | nil, float() | nil) ::
          :ok | {:warn, non_neg_integer(), float()}
  def check_limit(cumulative_tokens, client, limits \\ nil, threshold \\ nil)
      when is_integer(cumulative_tokens) do
    case get_limit(client, limits) do
      nil ->
        :ok

      limit ->
        threshold = get_warning_threshold(threshold)
        threshold_tokens = trunc(limit * threshold)

        if cumulative_tokens >= threshold_tokens do
          {:warn, limit, threshold}
        else
          :ok
        end
    end
  end
end
