defmodule AshAgent.Integration.ProgressiveDisclosureTest do
  @moduledoc """
  Integration tests for Progressive Disclosure hooks.
  Tests real workflows with tool result compaction, context compaction, and custom stopping conditions.
  Uses deterministic LLM stubs per AGENTS.md testing practices.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  defmodule TestHooks do
    @moduledoc false
    @behaviour AshAgent.Runtime.Hooks

    @impl true
    def prepare_tool_results(ctx) do
      truncated_results = Enum.map(ctx.results, &truncate_result/1)
      {:ok, truncated_results}
    end

    defp truncate_result({tool_name, {:ok, data}}) when is_binary(data) do
      if String.length(data) > 100 do
        {tool_name, {:ok, String.slice(data, 0, 100)}}
      else
        {tool_name, {:ok, data}}
      end
    end

    defp truncate_result({tool_name, result}), do: {tool_name, result}

    @impl true
    def prepare_context(ctx) do
      # Compact context - keep only last 3 iterations
      compacted_context =
        if map_size(ctx.context.iterations) > 3 do
          # Get iteration numbers sorted descending
          iteration_numbers =
            ctx.context.iterations
            |> Map.keys()
            |> Enum.sort(:desc)

          # Keep only last 3
          keep_iterations = Enum.take(iteration_numbers, 3)

          iterations_to_keep =
            Map.take(ctx.context.iterations, keep_iterations)

          %{ctx.context | iterations: iterations_to_keep}
        else
          ctx.context
        end

      {:ok, compacted_context}
    end

    @impl true
    def on_iteration_start(ctx) do
      # Custom stopping condition: stop after 3 iterations
      if ctx.iteration_number >= 3 do
        {:error,
         AshAgent.Error.llm_error("Custom stop condition reached", %{
           custom_limit: 3,
           current: ctx.iteration_number
         })}
      else
        {:ok, ctx}
      end
    end

    @impl true
    def on_iteration_complete(ctx) do
      # Send message to test process for verification
      test_pid = Process.get(:test_pid)

      if test_pid do
        send(test_pid, {:iteration_complete, ctx.iteration_number})
      end

      {:ok, ctx}
    end
  end

  describe "Progressive Disclosure Integration" do
    @tag :skip
    test "placeholder - integration tests coming in next iterations" do
      # This test is skipped because we need to create test resources and LLM stubs first
      # Will be implemented in subtasks 50-54
      assert true
    end
  end
end
