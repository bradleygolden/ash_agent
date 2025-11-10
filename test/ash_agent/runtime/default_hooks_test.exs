defmodule AshAgent.Runtime.DefaultHooksTest do
  use ExUnit.Case, async: true

  alias AshAgent.Context
  alias AshAgent.Error
  alias AshAgent.Runtime.DefaultHooks

  describe "on_iteration_start/1" do
    test "enforces max_iterations" do
      ctx = %{
        agent: MyAgent,
        iteration_number: 5,
        context: %Context{},
        result: nil,
        token_usage: nil,
        max_iterations: 5,
        client: "test"
      }

      assert {:error, %Error{type: :llm_error}} = DefaultHooks.on_iteration_start(ctx)
    end

    test "returns ok when under limit" do
      ctx = %{
        agent: MyAgent,
        iteration_number: 3,
        context: %Context{},
        result: nil,
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:ok, ^ctx} = DefaultHooks.on_iteration_start(ctx)
    end

    test "returns ok when exactly at limit minus one" do
      ctx = %{
        agent: MyAgent,
        iteration_number: 9,
        context: %Context{},
        result: nil,
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:ok, ^ctx} = DefaultHooks.on_iteration_start(ctx)
    end

    test "error contains max iterations in message" do
      ctx = %{
        agent: MyAgent,
        iteration_number: 10,
        context: %Context{},
        result: nil,
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:error, %Error{type: :llm_error, message: message, details: details}} =
               DefaultHooks.on_iteration_start(ctx)

      assert message == "Max iterations (10) exceeded"
      assert %{max: 10, current: 10} = details
    end
  end

  describe "on_iteration_complete/1" do
    test "returns ok when no token usage" do
      ctx = %{
        agent: MyAgent,
        iteration_number: 1,
        context: %Context{},
        result: :success,
        token_usage: nil,
        max_iterations: 10,
        client: "test"
      }

      assert {:ok, ^ctx} = DefaultHooks.on_iteration_complete(ctx)
    end

    test "returns ok when token usage present" do
      context = Context.new("test")
      context = Context.add_token_usage(context, %{input_tokens: 100, output_tokens: 50})

      ctx = %{
        agent: MyAgent,
        iteration_number: 1,
        context: context,
        result: :success,
        token_usage: %{input_tokens: 100, output_tokens: 50},
        max_iterations: 10,
        client: "anthropic/claude-3-5-sonnet-20241022"
      }

      assert {:ok, ^ctx} = DefaultHooks.on_iteration_complete(ctx)
    end

    test "checks token usage when present" do
      context = Context.new("test")
      context = Context.add_token_usage(context, %{input_tokens: 180_000, output_tokens: 7_000})

      ctx = %{
        agent: MyAgent,
        iteration_number: 1,
        context: context,
        result: :success,
        token_usage: %{input_tokens: 180_000, output_tokens: 7_000},
        max_iterations: 10,
        client: "anthropic:claude-3-5-sonnet"
      }

      assert {:ok, ^ctx} = DefaultHooks.on_iteration_complete(ctx)
    end

    test "handles token usage check without crashing" do
      context = Context.new("test")
      context = Context.add_token_usage(context, %{input_tokens: 100, output_tokens: 50})

      ctx = %{
        agent: MyAgent,
        iteration_number: 1,
        context: context,
        result: :success,
        token_usage: %{input_tokens: 100, output_tokens: 50},
        max_iterations: 10,
        client: "anthropic:claude-3-5-sonnet"
      }

      assert {:ok, ^ctx} = DefaultHooks.on_iteration_complete(ctx)
    end
  end
end
