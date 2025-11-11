defmodule ProgressiveDisclosureDemo.PDHooks do
  @moduledoc """
  Progressive Disclosure hooks demonstrating all major features.

  This hooks module showcases:
  - Result truncation for large data
  - Summarization of complex structures
  - Sampling of list results
  - Sliding window context compaction
  """

  @behaviour AshAgent.Runtime.Hooks

  alias AshAgent.ProgressiveDisclosure

  @impl true
  def prepare_tool_results(%{results: results}) do
    processed =
      ProgressiveDisclosure.process_tool_results(results,
        truncate: 500,
        summarize: true,
        sample: 3
      )

    {:ok, processed}
  end

  @impl true
  def prepare_context(%{context: context}) do
    compacted = ProgressiveDisclosure.sliding_window_compact(context, window_size: 3)
    {:ok, compacted}
  end

  @impl true
  def prepare_messages(%{messages: messages}), do: {:ok, messages}

  @impl true
  def on_iteration_start(%{context: context}), do: {:ok, context}

  @impl true
  def on_iteration_complete(%{context: context}), do: {:ok, context}
end
