defmodule AshAgent.Runtime.DefaultHooks do
  @moduledoc """
  Default hook implementations for AshAgent runtime.

  This module provides the standard behavior for iteration lifecycle hooks when
  no custom hooks are configured. It handles:

  - Max iterations enforcement (stops execution when limit reached)
  - Token usage tracking and warnings (emits telemetry when approaching limits)

  ## Automatic Execution

  These hooks run automatically when an agent does not specify custom hooks.
  This ensures existing behavior (max iterations, token warnings) continues
  working without any code changes.

  ## Composition Pattern

  Custom hooks can call these defaults to preserve standard behavior while
  adding custom logic:

      defmodule MyHooks do
        @behaviour AshAgent.Runtime.Hooks

        def on_iteration_start(ctx) do
          # Call default behavior first
          with {:ok, ctx} <- AshAgent.Runtime.DefaultHooks.on_iteration_start(ctx) do
            # Then add custom logic
            if my_custom_condition?(ctx) do
              {:error, AshAgent.Error.llm_error(message: "Custom stop")}
            else
              {:ok, ctx}
            end
          end
        end

        def on_iteration_complete(ctx) do
          # Call default behavior first
          with {:ok, ctx} <- AshAgent.Runtime.DefaultHooks.on_iteration_complete(ctx) do
            # Then add custom tracking
            track_iteration(ctx)
            {:ok, ctx}
          end
        end
      end

  ## Hook Behaviors

  ### on_iteration_start/1

  Enforces max iterations limit. Returns `{:error, reason}` when the current
  iteration exceeds `max_iterations`, causing the agent to stop execution.

  ### on_iteration_complete/1

  Checks token usage against client limits. Emits telemetry warnings when
  usage approaches or exceeds thresholds. Always returns `{:ok, ctx}` as
  warnings don't stop execution.
  """

  @behaviour AshAgent.Runtime.Hooks

  alias AshAgent.Error

  @doc """
  Enforces max iterations limit.

  Returns `{:error, reason}` if current iteration exceeds max_iterations,
  otherwise returns `{:ok, ctx}`.
  """
  @impl true
  def on_iteration_start(ctx) do
    if ctx.iteration_number >= ctx.max_iterations do
      {:error,
       Error.llm_error(
         message: "Max iterations (#{ctx.max_iterations}) exceeded",
         details: %{
           max: ctx.max_iterations,
           current: ctx.iteration_number
         }
       )}
    else
      {:ok, ctx}
    end
  end

  @doc """
  Checks token usage and emits warnings when approaching limits.

  Always returns `{:ok, ctx}` as token warnings don't stop execution.
  """
  @impl true
  def on_iteration_complete(ctx) do
    if ctx.token_usage do
      check_token_limit(ctx)
    end

    {:ok, ctx}
  end

  defp check_token_limit(ctx) do
    cumulative = AshAgent.Context.get_cumulative_tokens(ctx.context)

    case AshAgent.TokenLimits.check_limit(cumulative.total_tokens, ctx.client) do
      :ok ->
        :ok

      {:warn, limit, threshold} ->
        :telemetry.execute(
          [:ash_agent, :token_limit_warning],
          %{cumulative_tokens: cumulative.total_tokens},
          %{
            agent: ctx.agent,
            limit: limit,
            threshold_percent: trunc(threshold * 100),
            cumulative_tokens: cumulative.total_tokens
          }
        )
    end
  end
end
