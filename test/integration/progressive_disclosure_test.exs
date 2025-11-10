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
        if length(ctx.context.iterations) > 3 do
          # Keep only last 3 iterations
          iterations_to_keep = Enum.take(ctx.context.iterations, -3)

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

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule TestOutput do
    @moduledoc false
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute :result, :string, public?: true
    end
  end

  describe "tool result compaction" do
    test "truncates large tool results to 100 characters" do
      # Hooks that only truncate results (no custom stopping conditions)
      defmodule TruncateOnlyHooks do
        @moduledoc false
        @behaviour AshAgent.Runtime.Hooks

        @impl true
        def prepare_tool_results(ctx) do
          truncated_results =
            Enum.map(ctx.results, fn
              {tool_name, {:ok, data}} when is_binary(data) ->
                if String.length(data) > 100 do
                  {tool_name, {:ok, String.slice(data, 0, 100)}}
                else
                  {tool_name, {:ok, data}}
                end

              {tool_name, result} ->
                {tool_name, result}
            end)

          {:ok, truncated_results}
        end
      end

      # Create agent with truncate-only hooks
      defmodule ToolCompactionAgent do
        @moduledoc false
        use Ash.Resource,
          domain: AshAgent.Integration.ProgressiveDisclosureTest.TestDomain,
          extensions: [AshAgent.Resource]

        resource do
          require_primary_key? false
        end

        agent do
          client "test-stub:model"
          output AshAgent.Integration.ProgressiveDisclosureTest.TestOutput
          prompt "Get the large data"

          hooks AshAgent.Integration.ProgressiveDisclosureTest.ToolCompactionAgent.TruncateOnlyHooks
        end

        tools do
          max_iterations(2)

          tool :get_large_data do
            description("Returns a large string for testing")
            function({__MODULE__, :get_large_data_func, []})
          end
        end

        def get_large_data_func(_args, _context) do
          # Return deterministic large string (500 chars)
          {:ok, String.duplicate("A", 500)}
        end
      end

      # Stub LLM with sequence: first call tool, then return structured output
      alias AshAgent.Test.LLMStub
      call_count = :counters.new(1, [])

      Req.Test.stub(AshAgent.LLMStub, fn conn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          # First call: use the tool
          Req.Test.json(conn, %{
            "id" => "msg_test",
            "type" => "message",
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "tool_test",
                "name" => "get_large_data",
                "input" => %{}
              }
            ],
            "model" => "test-stub:model",
            "stop_reason" => "tool_use",
            "usage" => %{
              "input_tokens" => 100,
              "output_tokens" => 50
            }
          })
        else
          # Second call: return structured output
          Req.Test.json(conn, %{
            "id" => "msg_final",
            "type" => "message",
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "output_final",
                "name" => "structured_output",
                "input" => %{
                  "result" => "Done!"
                }
              }
            ],
            "model" => "test-stub:model",
            "stop_reason" => "tool_use",
            "usage" => %{
              "input_tokens" => 50,
              "output_tokens" => 25
            }
          })
        end
      end)

      # Call agent
      result = AshAgent.Runtime.call(ToolCompactionAgent, %{})

      # Verify tool was called and result was truncated
      assert {:ok, response} = result

      # Check that context contains truncated result (100 chars, not 500)
      assert response.context.iterations[1].tool_results != nil

      # Get the tool result from context
      tool_results = response.context.iterations[1].tool_results
      assert [{_tool_name, {:ok, truncated_data}}] = tool_results

      # Verify truncation happened (should be 100 chars, not 500)
      assert String.length(truncated_data) == 100
      assert truncated_data == String.duplicate("A", 100)
    end
  end
end
