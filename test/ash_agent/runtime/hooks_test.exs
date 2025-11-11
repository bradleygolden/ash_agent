defmodule AshAgent.Runtime.HooksTest do
  use ExUnit.Case, async: true

  alias AshAgent.Context
  alias AshAgent.Runtime.Hooks

  describe "prepare_tool_results/1 hook" do
    test "calls hook when implemented" do
      defmodule ToolResultHook do
        @behaviour Hooks

        def prepare_tool_results(%{results: results}) do
          modified =
            Enum.map(results, fn {name, {:ok, data}} ->
              {name, {:ok, "modified: #{data}"}}
            end)

          {:ok, modified}
        end
      end

      ctx = %{
        agent: MyAgent,
        iteration: 1,
        tool_calls: [%{"name" => "tool1"}],
        results: [{"tool1", {:ok, "original"}}],
        context: %Context{},
        token_usage: nil
      }

      assert {:ok, [{"tool1", {:ok, "modified: original"}}]} =
               Hooks.execute(ToolResultHook, :prepare_tool_results, ctx)
    end

    test "returns ok with context unchanged when not implemented" do
      defmodule NoToolResultHook do
        @behaviour Hooks
      end

      ctx = %{
        agent: MyAgent,
        iteration: 1,
        tool_calls: [],
        results: [{"tool1", {:ok, "data"}}],
        context: %Context{},
        token_usage: nil
      }

      assert {:ok, ^ctx} = Hooks.execute(NoToolResultHook, :prepare_tool_results, ctx)
    end

    test "can modify tool results" do
      defmodule TruncateHook do
        @behaviour Hooks

        def prepare_tool_results(%{results: results}) do
          truncated =
            Enum.map(results, fn
              {name, {:ok, data}} when is_binary(data) ->
                {name, {:ok, String.slice(data, 0, 10)}}

              other ->
                other
            end)

          {:ok, truncated}
        end
      end

      ctx = %{
        agent: MyAgent,
        iteration: 1,
        tool_calls: [],
        results: [{"tool1", {:ok, "this is a very long result that should be truncated"}}],
        context: %Context{},
        token_usage: nil
      }

      assert {:ok, [{"tool1", {:ok, "this is a "}}]} =
               Hooks.execute(TruncateHook, :prepare_tool_results, ctx)
    end

    test "handles errors returned by hook" do
      defmodule ErrorHook do
        @behaviour Hooks

        def prepare_tool_results(_ctx) do
          {:error, :something_went_wrong}
        end
      end

      ctx = %{
        agent: MyAgent,
        iteration: 1,
        tool_calls: [],
        results: [],
        context: %Context{},
        token_usage: nil
      }

      assert {:error, :something_went_wrong} =
               Hooks.execute(ErrorHook, :prepare_tool_results, ctx)
    end

    test "preserves error results" do
      defmodule ErrorPreservingHook do
        @behaviour Hooks

        def prepare_tool_results(%{results: results}) do
          modified =
            Enum.map(results, fn {name, result} ->
              case result do
                {:ok, data} ->
                  {name, {:ok, "modified: #{data}"}}

                error ->
                  {name, error}
              end
            end)

          {:ok, modified}
        end
      end

      ctx = %{
        agent: MyAgent,
        iteration: 1,
        tool_calls: [],
        results: [
          {"success_tool", {:ok, "data"}},
          {"error_tool", {:error, "tool failed"}}
        ],
        context: %Context{},
        token_usage: nil
      }

      assert {:ok, modified_results} =
               Hooks.execute(ErrorPreservingHook, :prepare_tool_results, ctx)

      assert [
               {"success_tool", {:ok, "modified: data"}},
               {"error_tool", {:error, "tool failed"}}
             ] = modified_results
    end

    test "hooks can be nil (no hooks configured)" do
      ctx = %{
        agent: TestAgent,
        iteration: 1,
        tool_calls: [],
        results: [{"tool", {:ok, "data"}}],
        context: %Context{},
        token_usage: nil
      }

      assert {:ok, ^ctx} = Hooks.execute(nil, :prepare_tool_results, ctx)
    end
  end

  describe "prepare_context/1 hook" do
    test "can modify context" do
      defmodule ContextModifyHook do
        @behaviour Hooks

        def prepare_context(%{context: ctx}) do
          modified = %{ctx | current_iteration: 999}
          {:ok, modified}
        end
      end

      ctx = %{
        agent: MyAgent,
        context: %Context{current_iteration: 1},
        token_usage: nil,
        iteration: 1
      }

      assert {:ok, %Context{current_iteration: 999}} =
               Hooks.execute(ContextModifyHook, :prepare_context, ctx)
    end

    test "returns error when hook fails" do
      defmodule ContextErrorHook do
        @behaviour Hooks

        def prepare_context(_ctx) do
          {:error, :context_preparation_failed}
        end
      end

      ctx = %{
        agent: MyAgent,
        context: %Context{},
        token_usage: nil,
        iteration: 1
      }

      assert {:error, :context_preparation_failed} =
               Hooks.execute(ContextErrorHook, :prepare_context, ctx)
    end

    test "receives correct context structure" do
      defmodule ContextStructureHook do
        @behaviour Hooks

        def prepare_context(%{agent: agent, context: context, token_usage: usage, iteration: i}) do
          assert agent == MyAgent
          assert %Context{} = context
          assert usage == %{input: 100, output: 50}
          assert i == 5
          {:ok, context}
        end
      end

      ctx = %{
        agent: MyAgent,
        context: %Context{},
        token_usage: %{input: 100, output: 50},
        iteration: 5
      }

      assert {:ok, %Context{}} = Hooks.execute(ContextStructureHook, :prepare_context, ctx)
    end

    test "hooks can be optional (not implemented)" do
      defmodule OptionalHooks do
        @behaviour Hooks

        def prepare_tool_results(%{results: results}) do
          {:ok, results}
        end
      end

      ctx = %{
        agent: TestAgent,
        context: %Context{},
        token_usage: nil,
        iteration: 1
      }

      assert {:ok, ^ctx} = Hooks.execute(OptionalHooks, :prepare_context, ctx)
    end
  end

  describe "prepare_messages/1 hook" do
    test "can add messages" do
      defmodule AddMessageHook do
        @behaviour Hooks

        def prepare_messages(%{messages: messages}) do
          augmented = messages ++ [%{"role" => "system", "content" => "Additional context"}]
          {:ok, augmented}
        end
      end

      ctx = %{
        agent: MyAgent,
        context: %Context{},
        messages: [%{"role" => "user", "content" => "Hello"}],
        tools: [],
        iteration: 1
      }

      assert {:ok, messages} = Hooks.execute(AddMessageHook, :prepare_messages, ctx)
      assert length(messages) == 2
      assert List.last(messages)["content"] == "Additional context"
    end

    test "can remove messages" do
      defmodule FilterMessageHook do
        @behaviour Hooks

        def prepare_messages(%{messages: messages}) do
          filtered = Enum.reject(messages, fn msg -> msg["role"] == "system" end)
          {:ok, filtered}
        end
      end

      ctx = %{
        agent: MyAgent,
        context: %Context{},
        messages: [
          %{"role" => "system", "content" => "System"},
          %{"role" => "user", "content" => "User"}
        ],
        tools: [],
        iteration: 1
      }

      assert {:ok, [%{"role" => "user"}]} =
               Hooks.execute(FilterMessageHook, :prepare_messages, ctx)
    end

    test "returns error when hook fails" do
      defmodule MessageErrorHook do
        @behaviour Hooks

        def prepare_messages(_ctx) do
          {:error, :message_preparation_failed}
        end
      end

      ctx = %{
        agent: MyAgent,
        context: %Context{},
        messages: [],
        tools: [],
        iteration: 1
      }

      assert {:error, :message_preparation_failed} =
               Hooks.execute(MessageErrorHook, :prepare_messages, ctx)
    end

    test "receives tools in context" do
      defmodule ToolsInContextHook do
        @behaviour Hooks

        def prepare_messages(%{tools: tools, messages: messages}) do
          assert length(tools) == 2
          assert Enum.all?(tools, &is_map/1)
          {:ok, messages}
        end
      end

      ctx = %{
        agent: MyAgent,
        context: %Context{},
        messages: [],
        tools: [%{"name" => "tool1"}, %{"name" => "tool2"}],
        iteration: 1
      }

      assert {:ok, []} = Hooks.execute(ToolsInContextHook, :prepare_messages, ctx)
    end
  end

  describe "on_iteration_start/1 hook" do
    test "can implement custom stopping conditions" do
      defmodule CustomStopHook do
        @behaviour Hooks

        def on_iteration_start(%{iteration_number: n} = ctx) do
          if n >= 5 do
            {:error, :custom_stop_condition}
          else
            {:ok, ctx}
          end
        end
      end

      ctx_ok = %{
        agent: MyAgent,
        iteration_number: 3,
        context: %Context{},
        result: nil,
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:ok, ^ctx_ok} = Hooks.execute(CustomStopHook, :on_iteration_start, ctx_ok)

      ctx_stop = %{ctx_ok | iteration_number: 5}

      assert {:error, :custom_stop_condition} =
               Hooks.execute(CustomStopHook, :on_iteration_start, ctx_stop)
    end

    test "can abort iteration by returning error" do
      defmodule AbortHook do
        @behaviour Hooks

        def on_iteration_start(_ctx) do
          {:error, :abort_now}
        end
      end

      ctx = %{
        agent: MyAgent,
        iteration_number: 1,
        context: %Context{},
        result: nil,
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:error, :abort_now} = Hooks.execute(AbortHook, :on_iteration_start, ctx)
    end

    test "allows iteration to proceed with ok" do
      defmodule ProceedHook do
        @behaviour Hooks

        def on_iteration_start(ctx) do
          {:ok, ctx}
        end
      end

      ctx = %{
        agent: MyAgent,
        iteration_number: 1,
        context: %Context{},
        result: nil,
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:ok, ^ctx} = Hooks.execute(ProceedHook, :on_iteration_start, ctx)
    end
  end

  describe "on_iteration_complete/1 hook" do
    test "is called after iteration" do
      defmodule TrackingHook do
        @behaviour Hooks

        def on_iteration_complete(ctx) do
          send(self(), {:iteration_complete, ctx.iteration_number})
          {:ok, ctx}
        end
      end

      ctx = %{
        agent: MyAgent,
        iteration_number: 3,
        context: %Context{},
        result: :success,
        token_usage: %{input: 100, output: 50},
        max_iterations: 10,
        client: "test"
      }

      assert {:ok, ^ctx} = Hooks.execute(TrackingHook, :on_iteration_complete, ctx)
      assert_received {:iteration_complete, 3}
    end

    test "receives iteration result in context" do
      defmodule ResultCheckHook do
        @behaviour Hooks

        def on_iteration_complete(%{result: result} = ctx) do
          assert result == {:ok, "iteration_result"}
          {:ok, ctx}
        end
      end

      ctx = %{
        agent: MyAgent,
        iteration_number: 1,
        context: %Context{},
        result: {:ok, "iteration_result"},
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:ok, ^ctx} = Hooks.execute(ResultCheckHook, :on_iteration_complete, ctx)
    end

    test "can perform side effects" do
      defmodule SideEffectHook do
        @behaviour Hooks

        def on_iteration_complete(ctx) do
          :ets.insert(:test_table, {ctx.iteration_number, ctx.result})
          {:ok, ctx}
        end
      end

      :ets.new(:test_table, [:named_table, :public])

      ctx = %{
        agent: MyAgent,
        iteration_number: 2,
        context: %Context{},
        result: :done,
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:ok, ^ctx} = Hooks.execute(SideEffectHook, :on_iteration_complete, ctx)
      assert [{2, :done}] = :ets.lookup(:test_table, 2)

      :ets.delete(:test_table)
    end

    test "errors returned by hook" do
      defmodule CompleteErrorHook do
        @behaviour Hooks

        def on_iteration_complete(_ctx) do
          {:error, :tracking_failed}
        end
      end

      ctx = %{
        agent: MyAgent,
        iteration_number: 1,
        context: %Context{},
        result: nil,
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:error, :tracking_failed} =
               Hooks.execute(CompleteErrorHook, :on_iteration_complete, ctx)
    end
  end
end
