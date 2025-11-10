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
  @spec get_limit(String.t() | atom(), map() | nil) :: non_neg_integer() | nil
  def get_limit(client, limits \\ nil) when is_binary(client) or is_atom(client) do
    limits = limits || Application.get_env(:ash_agent, :token_limits, %{})
    client_key = if is_atom(client), do: Atom.to_string(client), else: client
    Map.get(limits, client_key)
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
  Checks if cumulative tokens have exceeded the warning threshold or hard limit.

  Returns `{:error, :budget_exceeded}` if hard limit exceeded and strategy is :halt,
  `{:warn, limit, threshold}` if threshold exceeded,
  or `:ok` otherwise.

  ## Parameters
    - `cumulative_tokens` - The cumulative token count
    - `client` - The client identifier
    - `limits` - Optional limits map. If provided, uses this instead of application config.
    - `threshold` - Optional threshold value. If provided, uses this instead of application config.
    - `budget` - Optional hard budget limit. If provided and exceeded, returns error when strategy is :halt.
    - `strategy` - Budget enforcement strategy (:halt or :warn). Defaults to :warn.

  ## Examples

      iex> TokenLimits.check_limit(100_000, "anthropic:claude-3-5-sonnet")
      :ok

      iex> TokenLimits.check_limit(180_000, "anthropic:claude-3-5-sonnet")
      {:warn, 200_000, 0.8}

      iex> TokenLimits.check_limit(150_000, "anthropic:claude-3-5-sonnet", nil, nil, 100_000, :halt)
      {:error, :budget_exceeded}

      iex> TokenLimits.check_limit(150_000, "anthropic:claude-3-5-sonnet", nil, nil, 100_000, :warn)
      {:warn, 100_000, 0.8}
  """
  @spec check_limit(
          non_neg_integer(),
          String.t() | atom(),
          map() | nil,
          float() | nil,
          pos_integer() | nil,
          :halt | :warn
        ) ::
          :ok | {:warn, non_neg_integer(), float()} | {:error, :budget_exceeded}
  def check_limit(
        cumulative_tokens,
        client,
        limits \\ nil,
        threshold \\ nil,
        budget \\ nil,
        strategy \\ :warn
      )
      when is_integer(cumulative_tokens) do
    effective_limit = budget || get_limit(client, limits)

    cond do
      is_nil(effective_limit) ->
        :ok

      budget && strategy == :halt && cumulative_tokens >= budget ->
        {:error, :budget_exceeded}

      true ->
        check_warning_threshold(cumulative_tokens, effective_limit, threshold)
    end
  end

  defp check_warning_threshold(cumulative_tokens, limit, threshold) do
    threshold = get_warning_threshold(threshold)
    threshold_tokens = trunc(limit * threshold)

    if cumulative_tokens >= threshold_tokens do
      {:warn, limit, threshold}
    else
      :ok
    end
  end
end
