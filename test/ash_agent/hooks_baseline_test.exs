defmodule AshAgent.HooksBaselineTest do
  use ExUnit.Case, async: true

  alias AshAgent.{Context, Runtime.Hooks}

  describe "baseline hook functionality" do
    test "prepare_tool_results hook is called and modifies results" do
      defmodule TestHooks do
        @behaviour Hooks

        def prepare_tool_results(%{results: results}) do
          # Add marker to verify hook was called
          modified =
            Enum.map(results, fn {name, result} ->
              case result do
                {:ok, data} when is_binary(data) ->
                  {name <> "_hooked", {:ok, data <> " [HOOK_MARKER]"}}

                other ->
                  {name <> "_hooked", other}
              end
            end)

          {:ok, modified}
        end
      end

      ctx = %{
        agent: TestAgent,
        iteration: 1,
        tool_calls: [%{"name" => "get_data"}],
        results: [{"get_data", {:ok, "test data"}}],
        context: %Context{},
        token_usage: nil
      }

      assert {:ok, modified_results} = Hooks.execute(TestHooks, :prepare_tool_results, ctx)

      # Verify hook modified the tool name
      assert [{"get_data_hooked", {:ok, result_data}}] = modified_results

      # Verify hook marker is present
      assert String.contains?(result_data, "[HOOK_MARKER]")
      assert String.contains?(result_data, "test data")
    end

    test "prepare_context hook is called and modifies context" do
      defmodule ContextHooks do
        @behaviour Hooks

        def prepare_context(%{context: ctx}) do
          # Add an iteration to verify hook can modify context
          new_iteration = %{
            number: 999,
            messages: ["hook_was_here"],
            hook_marker: true
          }

          {:ok, %{ctx | iterations: [new_iteration | ctx.iterations]}}
        end
      end

      ctx = %{
        agent: TestAgent,
        context: %Context{iterations: []},
        token_usage: nil,
        iteration: 1
      }

      assert {:ok, modified_context} = Hooks.execute(ContextHooks, :prepare_context, ctx)

      # Verify hook modified the context
      assert %Context{} = modified_context
      assert length(modified_context.iterations) == 1
      assert [%{hook_marker: true, number: 999}] = modified_context.iterations
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

      # nil hooks should return context unchanged
      assert {:ok, ^ctx} = Hooks.execute(nil, :prepare_tool_results, ctx)
    end

    test "hooks can be optional (not implemented)" do
      defmodule OptionalHooks do
        @behaviour Hooks

        # Only implement one hook, not all
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

      # Should work fine when hook not implemented
      assert {:ok, ^ctx} = Hooks.execute(OptionalHooks, :prepare_context, ctx)
    end

    test "prepare_tool_results preserves error results" do
      defmodule ErrorPreservingHooks do
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
        agent: TestAgent,
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
               Hooks.execute(ErrorPreservingHooks, :prepare_tool_results, ctx)

      assert [
               {"success_tool", {:ok, "modified: data"}},
               {"error_tool", {:error, "tool failed"}}
             ] = modified_results
    end
  end
end
