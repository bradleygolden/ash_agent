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

    Uses default configuration: truncate to 100 bytes for testing.
    """
    @behaviour AshAgent.Runtime.Hooks

    def prepare_tool_results(%{results: results}) do
      # Use truncation for testing (max 100 bytes)
      processed = ProgressiveDisclosure.process_tool_results(results, truncate: 100)
      {:ok, processed}
    end

    def prepare_context(%{context: ctx}) do
      # No compaction by default in this test hook
      {:ok, ctx}
    end

    def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
    def on_iteration_start(ctx), do: {:ok, ctx}
    def on_iteration_complete(ctx), do: {:ok, ctx}
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
  # Subtask 4.2: Tool Result Truncation Integration Test
  # ============================================================================

  describe "tool result truncation" do
    defmodule TruncationTestAgent do
      @moduledoc """
      Agent that uses PDHooks for truncation testing.

      Returns large data from tools to demonstrate truncation.
      """
      use Ash.Resource,
        domain: TestDomain,
        extensions: [AshAgent.Resource]

      resource do
        require_primary_key? false
      end

      defmodule LargeOutput do
        use Ash.TypedStruct

        typed_struct do
          field :content, :string
        end
      end

      # Tool that returns large binary data
      def get_large_data(_args, _context) do
        # Generate ~10KB of data
        large_string = String.duplicate("Large data chunk. ", 500)
        {:ok, %{data: large_string}}
      end

      # Tool that returns small data
      def get_small_data(_args, _context) do
        {:ok, %{data: "Small data"}}
      end

      agent do
        provider :req_llm

        client("openai:qwen3:1.7b",
          base_url: "http://localhost:11434/v1",
          api_key: "ollama",
          temperature: 0.0
        )

        output LargeOutput

        input do
          argument :message, :string, allow_nil?: false
        end

        prompt """
        You are a test assistant.
        When asked for data, use the appropriate tool and return the result.
        Reply with JSON matching ctx.output_format exactly.
        {{ output_format }}
        """

        hooks PDHooks

        tools do
          max_iterations(3)
          timeout 30_000
          on_error(:continue)

          tool :get_large_data do
            description "Get large test data"
            function({__MODULE__, :get_large_data, []})
            parameters([])
          end

          tool :get_small_data do
            description "Get small test data"
            function({__MODULE__, :get_small_data, []})
            parameters([])
          end
        end
      end

      code_interface do
        define :call
      end
    end

    test "large tool results are truncated via hooks" do
      # Note: This test requires Ollama with qwen3:1.7b to be running
      # The hook is configured in PDHooks with truncate: 100
      result = TruncationTestAgent.call("Get large data")

      # Extract context safely
      context = extract_context!(result)

      # Verify agent executed at least one iteration
      iteration_count = Context.count_iterations(context)

      assert iteration_count > 0,
             "Agent did not iterate (count=#{iteration_count})"

      # Find iteration that called get_large_data tool
      iteration = find_iteration_with_tool!(context, "get_large_data")

      # Extract the tool result safely
      tool_result = extract_tool_result!(iteration, "get_large_data")

      # Verify result was truncated
      # Original result would be ~10KB (500 * 18 bytes)
      # Truncated result should be much smaller (~100 bytes + marker)
      result_size = byte_size(tool_result)

      assert result_size <= 200,
             "Result not truncated: #{result_size} bytes (expected ≤200)"

      # Verify truncation marker is present
      assert String.contains?(tool_result, "[truncated]") or
               String.contains?(tool_result, "..."),
             "Truncation marker not found in result"
    end

    test "small tool results are not truncated" do
      result = TruncationTestAgent.call("Get small data")

      context = extract_context!(result)
      iteration = find_iteration_with_tool!(context, "get_small_data")
      tool_result = extract_tool_result!(iteration, "get_small_data")

      # Small result should NOT contain truncation marker
      refute String.contains?(tool_result, "[truncated]"),
             "Small result was unexpectedly truncated"

      refute String.contains?(tool_result, "..."),
             "Small result was unexpectedly truncated"
    end
  end

  # ============================================================================
  # Subtask 4.3: Context Compaction Integration Tests
  # ============================================================================

  describe "context compaction with sliding window" do
    defmodule SlidingWindowHooks do
      @moduledoc """
      Hooks for testing sliding window compaction.
      Keeps only the last 2 iterations.
      """
      @behaviour AshAgent.Runtime.Hooks

      def prepare_tool_results(%{results: results}), do: {:ok, results}

      def prepare_context(%{context: ctx}) do
        # Apply sliding window: keep last 2 iterations
        compacted = ProgressiveDisclosure.sliding_window_compact(ctx, window_size: 2)
        {:ok, compacted}
      end

      def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
      def on_iteration_start(ctx), do: {:ok, ctx}
      def on_iteration_complete(ctx), do: {:ok, ctx}
    end

    defmodule CompactionTestAgent do
      @moduledoc """
      Agent for testing context compaction.
      Uses SlidingWindowHooks to compact context after each iteration.
      """
      use Ash.Resource,
        domain: AshAgent.TestDomain,
        data_layer: :embedded,
        extensions: [AshAgent.Resource]

      require Ash.Query

      attributes do
        uuid_primary_key :id
      end

      defmodule CompactionOutput do
        use Ash.TypedStruct

        typed_struct do
          field :result, :string
        end
      end

      # Tool that increments a counter (causes multiple iterations)
      def count_up(_args, _context) do
        {:ok, %{number: :rand.uniform(100)}}
      end

      agent do
        provider :req_llm

        client("openai:qwen3:1.7b",
          base_url: "http://localhost:11434/v1",
          api_key: "ollama",
          temperature: 0.0
        )

        output CompactionOutput

        input do
          argument :message, :string, allow_nil?: false
        end

        prompt """
        You are a counting assistant.
        Call the count_up tool multiple times.
        Reply with JSON matching ctx.output_format exactly.
        {{ output_format }}
        """

        hooks SlidingWindowHooks

        tools do
          max_iterations(5)
          timeout 30_000
          on_error(:continue)

          tool :count_up do
            description "Count up and return a number"
            function({__MODULE__, :count_up, []})
            parameters([])
          end
        end
      end

      code_interface do
        define :call
      end
    end

    test "old iterations are removed via sliding window compaction" do
      # Note: This test requires Ollama with qwen3:1.7b to be running
      # The hook is configured to keep only 2 iterations
      result = CompactionTestAgent.call("Count up multiple times")

      # Extract context safely
      context = extract_context!(result)

      # Verify agent executed multiple iterations
      iteration_count = Context.count_iterations(context)

      # The agent should have tried to iterate multiple times,
      # but sliding window should keep only last 2
      assert iteration_count > 0,
             "Agent did not iterate (count=#{iteration_count})"

      # With sliding window of 2, should never have more than 2 iterations
      assert iteration_count <= 2,
             "Sliding window failed: #{iteration_count} iterations (expected ≤2)"
    end

    test "compaction preserves most recent iterations" do
      # Note: This test requires Ollama with qwen3:1.7b to be running
      result = CompactionTestAgent.call("Count to three")

      context = extract_context!(result)

      # If we have 2 iterations, verify they are sequential (no gaps)
      if Context.count_iterations(context) == 2 do
        iteration_numbers = Enum.map(context.iterations, & &1.number)

        # Numbers should be consecutive (e.g., [2, 3] not [1, 3])
        [first, second] = Enum.sort(iteration_numbers)
        assert second - first <= 1, "Iterations have gaps: #{inspect(iteration_numbers)}"
      end
    end
  end

  # ============================================================================
  # Subtask 4.4: Token Budget Integration Tests
  # ============================================================================

  describe "token-based context compaction" do
    defmodule TokenBudgetHooks do
      @moduledoc """
      Hooks for testing token-based compaction.
      Enforces a low token budget to trigger compaction.
      """
      @behaviour AshAgent.Runtime.Hooks

      def prepare_tool_results(%{results: results}), do: {:ok, results}

      def prepare_context(%{context: ctx}) do
        # Apply token-based compaction with low budget (10,000 tokens)
        compacted = ProgressiveDisclosure.token_based_compact(ctx, budget: 10_000)
        {:ok, compacted}
      end

      def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
      def on_iteration_start(ctx), do: {:ok, ctx}
      def on_iteration_complete(ctx), do: {:ok, ctx}
    end

    defmodule TokenBudgetTestAgent do
      @moduledoc """
      Agent for testing token budget compaction.
      Uses TokenBudgetHooks to compact when approaching budget.
      """
      use Ash.Resource,
        domain: AshAgent.TestDomain,
        data_layer: :embedded,
        extensions: [AshAgent.Resource]

      require Ash.Query

      attributes do
        uuid_primary_key :id
      end

      defmodule BudgetOutput do
        use Ash.TypedStruct

        typed_struct do
          field :result, :string
        end
      end

      # Tool that returns verbose output (increases token usage)
      def verbose_operation(_args, _context) do
        # Return large-ish text to increase token count
        text = """
        This is a verbose operation result that contains many tokens.
        It includes detailed information, explanations, and examples.
        The purpose is to increase the token count of the context.
        #{String.duplicate("More text to add tokens. ", 20)}
        """

        {:ok, %{text: text}}
      end

      agent do
        provider :req_llm

        client("openai:qwen3:1.7b",
          base_url: "http://localhost:11434/v1",
          api_key: "ollama",
          temperature: 0.0
        )

        output BudgetOutput

        input do
          argument :message, :string, allow_nil?: false
        end

        prompt """
        You are a verbose assistant.
        Call the verbose_operation tool multiple times.
        Reply with JSON matching ctx.output_format exactly.
        {{ output_format }}
        """

        hooks TokenBudgetHooks

        tools do
          max_iterations(10)
          timeout 60_000
          on_error(:continue)

          tool :verbose_operation do
            description "Perform a verbose operation that returns lots of text"
            function({__MODULE__, :verbose_operation, []})
            parameters([])
          end
        end
      end

      code_interface do
        define :call
      end
    end

    test "compaction triggers when approaching token budget" do
      # Note: This test requires Ollama with qwen3:1.7b to be running
      # The hook is configured with a 10,000 token budget
      result = TokenBudgetTestAgent.call("Perform many verbose operations")

      # Extract context safely
      context = extract_context!(result)

      # Verify agent executed iterations
      iteration_count = Context.count_iterations(context)

      assert iteration_count > 0,
             "Agent did not iterate (count=#{iteration_count})"

      # Verify token count is under budget (with tolerance for estimation)
      estimated_tokens = Context.estimate_token_count(context)

      # Allow 20% margin due to estimation inaccuracy
      tolerance_budget = 10_000 * 1.2

      assert estimated_tokens <= tolerance_budget,
             "Token count (#{estimated_tokens}) exceeds budget with tolerance (#{tolerance_budget})"
    end

    test "compaction preserves at least one iteration" do
      # Note: This test requires Ollama with qwen3:1.7b to be running
      # Even with impossible budget, should keep 1 iteration for safety
      result = TokenBudgetTestAgent.call("Do one operation")

      context = extract_context!(result)
      iteration_count = Context.count_iterations(context)

      # Should have at least 1 iteration (safety constraint)
      assert iteration_count >= 1,
             "Compaction removed all iterations (unsafe)"
    end
  end

  # ============================================================================
  # Subtask 4.5: Processor Composition Integration Test
  # ============================================================================

  describe "processor composition" do
    # Agent that returns large data for testing composition
    defmodule CompositionTestHooks do
      @behaviour AshAgent.Runtime.Hooks

      alias AshAgent.ProgressiveDisclosure

      def prepare_tool_results(%{results: results}) do
        # Apply multiple processors in sequence
        processed =
          ProgressiveDisclosure.process_tool_results(results,
            truncate: 500,
            summarize: true,
            sample: 3
          )

        {:ok, processed}
      end

      def prepare_context(%{context: ctx}), do: {:ok, ctx}
      def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
      def on_iteration_start(%{context: ctx}), do: {:ok, ctx}
      def on_iteration_complete(%{context: ctx}), do: {:ok, ctx}
    end

    defmodule CompositionTestAgent do
      use Ash.Resource,
        domain: AshAgent.TestDomain,
        extensions: [AshAgent.Resource]

      resource do
        require_primary_key? false
      end

      defmodule CompositionOutput do
        use Ash.TypedStruct

        typed_struct do
          field :content, :string
        end
      end

      agent do
        client "baml:ollama/qwen2.5:3b"
        hooks CompositionTestHooks
        output CompositionOutput

        prompt """
        You are a test agent. When asked to get data, use the get_large_data tool.
        Return exactly what the tool returns without modification.
        """

        tools do
          max_iterations(5)
          timeout 30_000
          on_error(:continue)

          tool :get_large_data do
            description "Get large test data"
            function({LargeDataTool, :execute, []})
          end
        end
      end

      code_interface do
        define :call
      end
    end

    test "multiple processors compose correctly" do
      # Note: This test requires Ollama with qwen2.5:3b to be running
      result = CompositionTestAgent.call("Get large data using the tool")

      # Extract context safely
      context = extract_context!(result)

      # Verify agent executed
      assert Context.count_iterations(context) > 0, "Agent did not iterate"

      # Find iteration with tool call
      iteration = find_iteration_with_tool!(context, "get_large_data")

      # Extract tool result safely
      tool_result = extract_tool_result!(iteration, "get_large_data")

      # Result should be processed by all processors
      # The exact format depends on implementation, but it should be transformed
      result_size = :erlang.external_size(tool_result)

      # Original data is ~10KB, after truncate (500), summarize, and sample it should be much smaller
      assert result_size < 2000,
             "Result not processed by pipeline (size=#{result_size}, expected <2000)"

      # Verify agent completed successfully
      assert result.status in [:completed, :success], "Agent did not complete successfully"
    end

    test "processor pipeline is deterministic" do
      # Note: This test requires Ollama with qwen2.5:3b to be running
      # Same options should produce consistent processing
      result1 = CompositionTestAgent.call("Get large data using the tool")
      result2 = CompositionTestAgent.call("Get large data using the tool")

      # Extract contexts
      context1 = extract_context!(result1)
      context2 = extract_context!(result2)

      # Find iterations with tool calls
      iter1 = find_iteration_with_tool!(context1, "get_large_data")
      iter2 = find_iteration_with_tool!(context2, "get_large_data")

      # Extract tool results
      result1_data = extract_tool_result!(iter1, "get_large_data")
      result2_data = extract_tool_result!(iter2, "get_large_data")

      # Both results should be processed identically (deterministic composition)
      # Compare sizes since exact content may vary but processing should be consistent
      size1 = :erlang.external_size(result1_data)
      size2 = :erlang.external_size(result2_data)

      # Allow small variance (within 10%) for minor differences
      variance = abs(size1 - size2) / max(size1, size2)

      assert variance < 0.1,
             "Processor composition is non-deterministic (size1=#{size1}, size2=#{size2}, variance=#{Float.round(variance * 100, 1)}%)"
    end

    test "composition handles empty results gracefully" do
      # Note: This test requires Ollama with qwen2.5:3b to be running
      # Agent may not call tools, or tools may return empty results
      result = CompositionTestAgent.call("Say hello without using any tools")

      # Extract context safely
      context = extract_context!(result)

      # Agent should still complete successfully even with no tool results to process
      assert result.status in [:completed, :success], "Agent did not complete successfully"
      assert Context.count_iterations(context) > 0, "Agent did not iterate"
    end
  end
end
