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

  # Public API will be implemented in subsequent subtasks
end
