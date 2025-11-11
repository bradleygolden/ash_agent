defmodule AshAgent.ProgressiveDisclosure do
  @moduledoc """
  Helper utilities for implementing Progressive Disclosure patterns.

  This module provides high-level functions for common Progressive Disclosure
  scenarios:

  - **Result Processing**: Truncate, summarize, or sample large tool results
  - **Context Compaction**: Remove old iterations using sliding window or token budget

  ## Quick Start

  Use in your hook implementations:

      defmodule MyApp.PDHooks do
        @behaviour AshAgent.Runtime.Hooks

        alias AshAgent.ProgressiveDisclosure

        def prepare_tool_results(%{results: results}) do
          processed = ProgressiveDisclosure.process_tool_results(results,
            truncate: 1000,
            summarize: true,
            sample: 5
          )
          {:ok, processed}
        end

        def prepare_context(%{context: ctx}) do
          compacted = ProgressiveDisclosure.sliding_window_compact(ctx, window_size: 5)
          {:ok, compacted}
        end
      end

  ## Architecture

  This module serves as a **convenience layer** over:
  - `AshAgent.ResultProcessors.*` - Individual result processors
  - `AshAgent.Context` helpers - Context manipulation functions

  It provides:
  - Processor composition (apply multiple processors in sequence)
  - Common compaction strategies (sliding window, token-based)
  - Telemetry integration (track PD usage)
  - Sensible defaults (skip processing for small results)

  ## See Also

  - Progressive Disclosure Guide: `documentation/guides/progressive-disclosure.md`
  - Hook System: `AshAgent.Runtime.Hooks`
  - Result Processors: `AshAgent.ResultProcessors.*`
  """

  alias AshAgent.{Context, ResultProcessors}
  require Logger

  @doc """
  Applies a standard tool result processing pipeline.

  Composes multiple processors in sequence:
  1. Check if any results are large (skip processing if all small)
  2. Apply truncation (if configured)
  3. Apply summarization (if configured)
  4. Apply sampling (if configured)
  5. Emit telemetry

  ## Options

  - `:truncate` - Max size for truncation (integer, default: no truncation)
  - `:summarize` - Enable summarization (boolean or keyword, default: false)
  - `:sample` - Sample size for lists (integer, default: no sampling)
  - `:skip_small` - Skip processing if all results under threshold (boolean, default: true)

  ## Examples

      iex> results = [{"query", {:ok, large_data}}]
      iex> processed = ProgressiveDisclosure.process_tool_results(results,
      ...>   truncate: 1000,
      ...>   summarize: true
      ...> )

  ## Telemetry

  Emits `[:ash_agent, :progressive_disclosure, :process_results]` event with:
  - Measurements: `%{count: integer(), skipped: boolean()}`
  - Metadata: `%{options: keyword()}`
  """
  @spec process_tool_results([AshAgent.ResultProcessor.result_entry()], keyword()) ::
          [AshAgent.ResultProcessor.result_entry()]
  def process_tool_results(results, opts \\ []) do
    skip_small? = Keyword.get(opts, :skip_small, true)

    results
    |> maybe_skip_small(skip_small?, opts)
    |> apply_truncate(opts)
    |> apply_summarize(opts)
    |> apply_sample(opts)
    |> emit_processing_telemetry(opts)
  end

  defp maybe_skip_small(results, false, _opts), do: {:process, results}

  defp maybe_skip_small(results, true, opts) do
    truncate_threshold = Keyword.get(opts, :truncate, :infinity)

    has_large_result? =
      Enum.any?(results, fn
        {_name, {:ok, data}} ->
          ResultProcessors.estimate_size(data) > truncate_threshold

        _ ->
          false
      end)

    if has_large_result? do
      {:process, results}
    else
      Logger.debug("All results under threshold, skipping processing")
      {:skip, results}
    end
  end

  defp apply_truncate({:skip, results}, _opts), do: {:skip, results}

  defp apply_truncate({:process, results}, opts) do
    case Keyword.get(opts, :truncate) do
      nil ->
        {:process, results}

      max_size when is_integer(max_size) ->
        Logger.debug("Truncating results to max_size=#{max_size}")
        truncated = ResultProcessors.Truncate.process(results, max_size: max_size)
        {:process, truncated}
    end
  end

  defp apply_summarize({:skip, results}, _opts), do: {:skip, results}

  defp apply_summarize({:process, results}, opts) do
    summarize_opts = Keyword.get(opts, :summarize, false)

    cond do
      summarize_opts == false ->
        {:process, results}

      summarize_opts == true ->
        Logger.debug("Summarizing results with defaults")
        summarized = ResultProcessors.Summarize.process(results, [])
        {:process, summarized}

      is_list(summarize_opts) ->
        Logger.debug("Summarizing results with options: #{inspect(summarize_opts)}")
        summarized = ResultProcessors.Summarize.process(results, summarize_opts)
        {:process, summarized}
    end
  end

  defp apply_sample({:skip, results}, _opts), do: {:skip, results}

  defp apply_sample({:process, results}, opts) do
    case Keyword.get(opts, :sample) do
      nil ->
        {:process, results}

      sample_size when is_integer(sample_size) ->
        Logger.debug("Sampling results with size=#{sample_size}")
        sampled = ResultProcessors.Sample.process(results, sample_size: sample_size)
        {:process, sampled}
    end
  end

  defp emit_processing_telemetry({:skip, results}, opts) do
    :telemetry.execute(
      [:ash_agent, :progressive_disclosure, :process_results],
      %{count: length(results), skipped: true},
      %{options: opts}
    )

    results
  end

  defp emit_processing_telemetry({:process, results}, opts) do
    :telemetry.execute(
      [:ash_agent, :progressive_disclosure, :process_results],
      %{count: length(results), skipped: false},
      %{options: opts}
    )

    results
  end

  @doc """
  Applies sliding window context compaction.

  Keeps the last N iterations in full detail, removes older ones.
  This is the **simplest** and most **predictable** compaction strategy.

  ## Options

  - `:window_size` - Number of recent iterations to keep (required)

  ## Examples

      iex> context = %AshAgent.Context{iterations: [1, 2, 3, 4, 5]}
      iex> compacted = AshAgent.ProgressiveDisclosure.sliding_window_compact(
      ...>   context,
      ...>   window_size: 3
      ...> )
      iex> length(compacted.iterations)
      3

  ## When to Use

  - Fixed iteration history limit
  - Predictable memory usage
  - Simple configuration

  ## Telemetry

  Emits `[:ash_agent, :progressive_disclosure, :sliding_window]` event with:
  - Measurements: `%{before_count: int, after_count: int, removed: int}`
  - Metadata: `%{window_size: int}`
  """
  @spec sliding_window_compact(Context.t(), keyword()) :: Context.t()
  def sliding_window_compact(%Context{} = context, opts) do
    window_size = Keyword.fetch!(opts, :window_size)

    unless is_integer(window_size) and window_size > 0 do
      raise ArgumentError, "window_size must be a positive integer, got: #{inspect(window_size)}"
    end

    before_count = Context.count_iterations(context)

    Logger.debug("Applying sliding window compaction with window_size=#{window_size}")

    compacted = Context.keep_last_iterations(context, window_size)

    after_count = Context.count_iterations(compacted)
    removed = before_count - after_count

    if removed > 0 do
      Logger.info("Sliding window compaction removed #{removed} iterations")
    end

    :telemetry.execute(
      [:ash_agent, :progressive_disclosure, :sliding_window],
      %{
        before_count: before_count,
        after_count: after_count,
        removed: removed
      },
      %{window_size: window_size}
    )

    compacted
  end
end
