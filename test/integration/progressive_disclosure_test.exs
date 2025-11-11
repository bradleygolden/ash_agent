defmodule AshAgent.Integration.ProgressiveDisclosureTest do
  @moduledoc """
  Integration tests for Progressive Disclosure features.

  Tests demonstrate PD features working in real agent workflows with
  pattern matching assertions and nil-safe helpers (per Skinner's requirements).
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias AshAgent.{Context, ProgressiveDisclosure}

  # ============================================================================
  # Test Infrastructure
  # ============================================================================

  defmodule PDHooks do
    @moduledoc """
    Hooks module implementing Progressive Disclosure patterns.

    Configuration can be overridden per test via state map.
    """
    @behaviour AshAgent.Runtime.Hooks

    def prepare_tool_results(%{results: results} = state) do
      opts = Map.get(state, :pd_result_opts, [])
      processed = ProgressiveDisclosure.process_tool_results(results, opts)
      {:ok, processed}
    end

    def prepare_context(%{context: ctx} = state) do
      opts = Map.get(state, :pd_context_opts, [])

      compacted =
        case Keyword.get(opts, :strategy) do
          :sliding_window ->
            window_size = Keyword.fetch!(opts, :window_size)
            ProgressiveDisclosure.sliding_window_compact(ctx, window_size: window_size)

          :token_based ->
            budget = Keyword.fetch!(opts, :budget)
            threshold = Keyword.get(opts, :threshold, 1.0)
            ProgressiveDisclosure.token_based_compact(ctx, budget: budget, threshold: threshold)

          nil ->
            ctx
        end

      {:ok, compacted}
    end

    def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
    def on_iteration_start(%{iteration_context: ctx}), do: {:ok, ctx}
    def on_iteration_complete(%{iteration_context: ctx}), do: {:ok, ctx}
  end

  # ============================================================================
  # Safe Helper Functions (Addressing Skinner's Issue #2)
  # ============================================================================

  @doc """
  Safely extract context from result with pattern matching.

  Crashes with clear error message if result doesn't match expected format.
  """
  def extract_context!(result) do
    assert %Context{} = result, "Expected Context struct, got: #{inspect(result)}"
    result
  end

  @doc """
  Find iteration that used a specific tool.

  Crashes with clear error if no iteration found with that tool.
  """
  def find_iteration_with_tool!(context, tool_name) do
    iteration = Enum.find(context.iterations, &iteration_has_tool?(&1, tool_name))
    assert iteration != nil, "No iteration found using tool: #{tool_name}"
    iteration
  end

  # Helper: Check if iteration contains a message with the specified tool call
  defp iteration_has_tool?(iteration, tool_name) do
    messages = Map.get(iteration, :messages, [])
    Enum.any?(messages, &message_has_tool?(&1, tool_name))
  end

  # Helper: Check if message contains the specified tool call
  defp message_has_tool?(message, tool_name) do
    tool_calls = Map.get(message, :tool_calls, [])
    Enum.any?(tool_calls, fn tc -> tc["name"] == tool_name end)
  end

  @doc """
  Extract tool result from iteration safely.

  Crashes with clear error if tool result not found.
  """
  def extract_tool_result!(iteration, tool_name) do
    messages = Map.get(iteration, :messages, [])
    assert length(messages) > 0, "No messages in iteration"

    # Find tool result message
    result_msg =
      Enum.find(messages, fn msg ->
        Map.get(msg, :role) == "tool" and Map.get(msg, :name) == tool_name
      end)

    assert result_msg != nil, "Tool result message not found for: #{tool_name}"

    content = Map.get(result_msg, :content)
    assert content != nil, "Tool result content is nil"

    content
  end

  # ============================================================================
  # Tests Will Be Added Here
  # ============================================================================

  describe "progressive disclosure infrastructure" do
    test "PDHooks module implements all required callbacks" do
      # Verify hooks module compiles and has correct behavior
      assert function_exported?(PDHooks, :prepare_tool_results, 1)
      assert function_exported?(PDHooks, :prepare_context, 1)
      assert function_exported?(PDHooks, :prepare_messages, 1)
      assert function_exported?(PDHooks, :on_iteration_start, 1)
      assert function_exported?(PDHooks, :on_iteration_complete, 1)
    end

    test "helper functions handle nil cases safely" do
      # Test that helpers crash with clear messages on nil input
      assert_raise MatchError, fn ->
        extract_context!(nil)
      end

      assert_raise MatchError, fn ->
        extract_context!(%{not_a: :context})
      end
    end

    test "context extraction works with valid context" do
      context = %Context{}
      assert %Context{} = extract_context!(context)
    end
  end

  # ============================================================================
  # Placeholder for future subtasks
  # ============================================================================
  # Subtask 4.2: Tool Result Truncation Integration Test
  # Subtask 4.3: Context Compaction Integration Test
  # Subtask 4.4: Token Budget Integration Test
  # Subtask 4.5: Processor Composition Integration Test
end
