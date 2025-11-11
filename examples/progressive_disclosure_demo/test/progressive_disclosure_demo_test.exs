defmodule ProgressiveDisclosureDemoTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias AshAgent.Context

  describe "demo agent with PD hooks" do
    test "processes large results with token savings" do
      result =
        AshAgent.call(
          ProgressiveDisclosureDemo.DemoAgent,
          "Get the large dataset"
        )

      assert {:ok, %{context: context}} = result

      iteration_count = Context.count_iterations(context)
      assert iteration_count > 0, "Agent should execute at least one iteration"

      estimated_tokens = Context.estimate_token_count(context)
      assert estimated_tokens < 10_000, "PD should reduce token usage significantly"
    end

    test "PD hooks don't break agent execution" do
      result =
        AshAgent.call(
          ProgressiveDisclosureDemo.DemoAgent,
          "Get the user list and tell me how many users there are"
        )

      assert {:ok, response} = result
      assert response.final_response != nil, "Agent should produce a response"
    end

    test "multiple tool calls with PD processing" do
      result =
        AshAgent.call(
          ProgressiveDisclosureDemo.DemoAgent,
          "Get the large dataset, then get the user list, then summarize both"
        )

      assert {:ok, %{context: context}} = result

      iterations_with_tools =
        Enum.count(context.iterations, fn iter ->
          tool_calls = Map.get(iter, :tool_calls, [])
          length(tool_calls) > 0
        end)

      assert iterations_with_tools >= 1, "Should have iterations with tool calls"

      estimated_tokens = Context.estimate_token_count(context)
      assert estimated_tokens < 20_000, "PD should keep tokens reasonable with multiple tools"
    end
  end

  describe "demo tools" do
    test "get_large_dataset returns large data" do
      assert {:ok, data} = ProgressiveDisclosureDemo.Tools.get_large_dataset()
      assert is_binary(data)
      assert byte_size(data) > 5_000, "Should return substantial data"
    end

    test "get_user_list returns list of users" do
      assert {:ok, users} = ProgressiveDisclosureDemo.Tools.get_user_list()
      assert is_list(users)
      assert length(users) == 100, "Should return 100 users"
    end

    test "get_log_data returns log entries" do
      assert {:ok, logs} = ProgressiveDisclosureDemo.Tools.get_log_data()
      assert is_binary(logs)
      assert String.contains?(logs, "Log entry")
    end
  end
end
