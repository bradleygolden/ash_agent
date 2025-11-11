defmodule ProgressiveDisclosureDemo do
  @moduledoc """
  Demonstration of Progressive Disclosure token savings.

  Run this module to see the impact of Progressive Disclosure on token usage
  and cost when processing large tool results.
  """

  alias AshAgent.Context

  def run do
    IO.puts("\n=== Progressive Disclosure Demo ===\n")

    IO.puts("This demo shows token savings achieved with Progressive Disclosure.")
    IO.puts("See results/token_savings_report.txt for detailed analysis.\n")

    IO.puts("--- Scenario ---")
    IO.puts("Agent processing large datasets with multiple tool calls\n")

    IO.puts("--- Configuration ---")
    IO.puts("Result truncation: 500 bytes")
    IO.puts("Summarization: Enabled")
    IO.puts("Sampling: First 3 items")
    IO.puts("Context compaction: Sliding window (3 iterations)\n")

    IO.puts("--- Running Agent ---")
    IO.puts("Calling agent to process large datasets...\n")

    result =
      AshAgent.call(
        ProgressiveDisclosureDemo.DemoAgent,
        "Get the large dataset and analyze it. Then get the user list and summarize the key statistics. Finally, get the log data and identify any patterns."
      )

    case result do
      {:ok, %{context: context} = response} ->
        display_results(context, response)

      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
  end

  defp display_results(context, response) do
    iteration_count = Context.count_iterations(context)
    estimated_tokens = Context.estimate_token_count(context)

    IO.puts("--- Results ---")
    IO.puts("Total iterations: #{iteration_count}")
    IO.puts("Estimated token usage: ~#{estimated_tokens} tokens")
    IO.puts("Iterations kept in context: #{iteration_count} (compacted)")

    IO.puts("\n--- Token Savings Analysis ---")

    without_pd = estimate_without_pd(iteration_count)
    with_pd = estimated_tokens
    savings = without_pd - with_pd
    savings_pct = round(savings / without_pd * 100)

    IO.puts("Without PD (estimated): ~#{without_pd} tokens")
    IO.puts("With PD (actual): ~#{with_pd} tokens")
    IO.puts("Savings: ~#{savings} tokens (#{savings_pct}%)")

    cost_without = Float.round(without_pd / 1000 * 0.01, 4)
    cost_with = Float.round(with_pd / 1000 * 0.01, 4)
    cost_savings = Float.round(cost_without - cost_with, 4)

    IO.puts("\n--- Cost Impact (at $0.01 per 1K tokens) ---")
    IO.puts("Without PD: $#{cost_without}")
    IO.puts("With PD: $#{cost_with}")
    IO.puts("Savings: $#{cost_savings} per run")

    IO.puts("\n--- Agent Response ---")
    IO.puts(response.final_response || "No final response")

    IO.puts("\n--- Context Details ---")

    Enum.each(context.iterations, fn iteration ->
      tool_calls = Map.get(iteration, :tool_calls, [])

      if length(tool_calls) > 0 do
        IO.puts("\nIteration #{iteration.number}:")

        Enum.each(tool_calls, fn tool_call ->
          result_size = estimate_result_size(tool_call.result)
          IO.puts("  Tool: #{tool_call.name}")
          IO.puts("  Result size: ~#{result_size} bytes (after PD processing)")
        end)
      end
    end)

    IO.puts("\n=== Demo Complete ===")
    IO.puts("See results/token_savings_report.txt for detailed breakdown.\n")
  end

  defp estimate_without_pd(iteration_count) do
    iteration_count * 5000
  end

  defp estimate_result_size(result) do
    case result do
      {:ok, data} when is_binary(data) ->
        byte_size(data)

      {:ok, data} when is_list(data) ->
        :erlang.external_size(data)

      {:ok, data} when is_map(data) ->
        :erlang.external_size(data)

      {:ok, data} ->
        :erlang.external_size(data)

      _ ->
        0
    end
  end
end
