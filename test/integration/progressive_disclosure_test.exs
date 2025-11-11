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
        define :call, args: [:message]
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
  # Placeholder for future subtasks
  # ============================================================================
  # Subtask 4.3: Context Compaction Integration Test
  # Subtask 4.4: Token Budget Integration Test
  # Subtask 4.5: Processor Composition Integration Test
end
