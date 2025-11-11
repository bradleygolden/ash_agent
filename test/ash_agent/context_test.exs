defmodule AshAgent.ContextTest do
  use ExUnit.Case, async: true

  doctest AshAgent.Context

  alias AshAgent.Context

  describe "new/2" do
    test "creates a new context with initial user message" do
      context = Context.new("Hello", [])

      assert context.current_iteration == 1
      assert length(context.iterations) == 1

      [iteration] = context.iterations
      assert iteration.number == 1
      assert length(iteration.messages) == 1

      [message] = iteration.messages
      assert message.role == :user
      assert message.content == "Hello"
    end

    test "creates context with system prompt option" do
      context = Context.new("Hello", system_prompt: "You are helpful")

      [iteration] = context.iterations
      assert length(iteration.messages) == 2

      [system_message, user_message] = iteration.messages
      assert system_message.role == :system
      assert system_message.content == "You are helpful"
      assert user_message.role == :user
      assert user_message.content == "Hello"
    end

    test "handles map input without message key" do
      context = Context.new(%{data: "test"}, [])

      [iteration] = context.iterations
      [message] = iteration.messages
      assert message.role == :user
      assert is_binary(message.content)
    end
  end

  describe "add_assistant_message/3" do
    test "adds assistant message to current iteration" do
      context = Context.new("Hello", [])
      context = Context.add_assistant_message(context, "Hi there!")

      assert context.current_iteration == 1
      assert length(context.iterations) == 1

      [iteration] = context.iterations
      assert iteration.number == 1
      assert length(iteration.messages) == 2

      [_, assistant_message] = iteration.messages
      assert assistant_message.role == :assistant
      assert assistant_message.content == "Hi there!"
      assert assistant_message.tool_calls == nil
    end

    test "adds assistant message with tool calls" do
      context = Context.new("Hello", [])
      tool_calls = [%{id: "call_1", name: "get_weather", arguments: %{city: "NYC"}}]

      context = Context.add_assistant_message(context, "Let me check", tool_calls)

      assert context.current_iteration == 1
      assert length(context.iterations) == 1

      [iteration] = context.iterations
      [_, assistant_message] = iteration.messages
      assert assistant_message.role == :assistant
      assert assistant_message.content == "Let me check"
      assert assistant_message.tool_calls == tool_calls
    end

    test "carries forward messages in same iteration" do
      context = Context.new("Hello", system_prompt: "Be helpful")
      context = Context.add_assistant_message(context, "Response 1")

      [iteration] = context.iterations
      assert length(iteration.messages) == 3

      [system, user, assistant] = iteration.messages
      assert system.role == :system
      assert user.role == :user
      assert assistant.role == :assistant
    end
  end

  describe "add_tool_results/2" do
    test "adds tool results to current iteration" do
      context = Context.new("Hello", [])

      context =
        Context.add_assistant_message(context, "Checking", [
          %{id: "call_1", name: "get_weather", arguments: %{}}
        ])

      results = [
        {"call_1", {:ok, %{temperature: 72}}}
      ]

      context = Context.add_tool_results(context, results)

      assert context.current_iteration == 1
      assert length(context.iterations) == 1

      [iteration] = context.iterations
      assert iteration.number == 1
      assert length(iteration.messages) == 3

      [_, _, result_message] = iteration.messages
      assert result_message.role == :user
      assert is_list(result_message.content)
      assert length(result_message.content) == 1

      [content_part] = result_message.content
      assert content_part.type == :tool_result
      assert content_part.tool_use_id == "call_1"
      assert is_binary(content_part.content)
    end

    test "handles tool errors" do
      context = Context.new("Hello", [])

      context =
        Context.add_assistant_message(context, "Checking", [
          %{id: "call_1", name: "get_weather", arguments: %{}}
        ])

      results = [
        {"call_1", {:error, "API unavailable"}}
      ]

      context = Context.add_tool_results(context, results)

      [iteration] = context.iterations
      [_, _, result_message] = iteration.messages
      [content_part] = result_message.content
      assert content_part.type == :tool_result
      assert is_binary(content_part.content)
    end
  end

  describe "exceeded_max_iterations?/2" do
    test "returns false when under max iterations" do
      context = Context.new("Hello", [])

      refute Context.exceeded_max_iterations?(context, 5)
    end

    test "returns true when at max iterations" do
      context = Context.new("Hello", [])

      assert Context.exceeded_max_iterations?(context, 1)
    end

    test "returns false when below max iterations" do
      context = Context.new("Hello", [])

      refute Context.exceeded_max_iterations?(context, 2)
    end
  end

  describe "extract_tool_calls/1" do
    test "extracts tool calls from last assistant message" do
      context = Context.new("Hello", [])
      tool_calls = [%{id: "call_1", name: "get_weather", arguments: %{}}]

      context = Context.add_assistant_message(context, "Checking", tool_calls)

      assert Context.extract_tool_calls(context) == tool_calls
    end

    test "returns empty list when no tool calls" do
      context = Context.new("Hello", [])
      context = Context.add_assistant_message(context, "No tools")

      assert Context.extract_tool_calls(context) == []
    end

    test "returns empty list when last message is not assistant" do
      context = Context.new("Hello", [])

      assert Context.extract_tool_calls(context) == []
    end
  end

  describe "to_messages/1" do
    test "converts context to provider message format" do
      context = Context.new("Hello", [])
      context = Context.add_assistant_message(context, "Hi there!")

      messages = Context.to_messages(context)

      assert length(messages) == 2
      assert hd(messages).role == "user"
      assert List.last(messages).role == "assistant"
    end

    test "formats tool calls in messages" do
      context = Context.new("Hello", [])
      tool_calls = [%{id: "call_1", name: "get_weather", arguments: %{city: "NYC"}}]

      context = Context.add_assistant_message(context, "Checking", tool_calls)

      messages = Context.to_messages(context)
      assistant_message = List.last(messages)

      assert assistant_message.role == "assistant"
      assert is_list(assistant_message.tool_calls)
      assert length(assistant_message.tool_calls) == 1

      [tool_call] = assistant_message.tool_calls
      assert tool_call.id == "call_1"
      assert tool_call.function.name == "get_weather"
    end

    test "formats tool results in messages" do
      context = Context.new("Hello", [])

      context =
        Context.add_assistant_message(context, "Checking", [
          %{id: "call_1", name: "get_weather", arguments: %{}}
        ])

      results = [{"call_1", {:ok, %{temperature: 72}}}]
      context = Context.add_tool_results(context, results)

      messages = Context.to_messages(context)
      assert length(messages) == 3

      result_message = Enum.at(messages, 2)
      assert result_message.role == "user"
      assert is_list(result_message.content)
    end
  end

  describe "get_iteration/2" do
    test "retrieves specific iteration by number" do
      context = Context.new("Hello", [])

      iteration = Context.get_iteration(context, 1)
      assert iteration.number == 1
      assert length(iteration.messages) == 1
    end

    test "returns nil for non-existent iteration" do
      context = Context.new("Hello", [])

      assert Context.get_iteration(context, 99) == nil
    end

    test "returns nil for negative iteration number" do
      context = Context.new("Hello", [])

      assert Context.get_iteration(context, -1) == nil
    end
  end

  describe "add_token_usage/2" do
    test "adds token usage to current iteration metadata" do
      context = Context.new("Hello", [])
      usage = %{input_tokens: 100, output_tokens: 50, total_tokens: 150}

      context = Context.add_token_usage(context, usage)

      iteration = Context.get_iteration(context, 1)
      assert iteration.metadata.current_usage == usage
      assert iteration.metadata.cumulative_tokens.input_tokens == 100
      assert iteration.metadata.cumulative_tokens.output_tokens == 50
      assert iteration.metadata.cumulative_tokens.total_tokens == 150
    end

    test "accumulates token usage across multiple calls" do
      context = Context.new("Hello", [])
      usage1 = %{input_tokens: 100, output_tokens: 50, total_tokens: 150}
      usage2 = %{input_tokens: 75, output_tokens: 25, total_tokens: 100}

      context = Context.add_token_usage(context, usage1)
      context = Context.add_token_usage(context, usage2)

      cumulative = Context.get_cumulative_tokens(context)
      assert cumulative.input_tokens == 175
      assert cumulative.output_tokens == 75
      assert cumulative.total_tokens == 250
    end

    test "handles partial usage maps and calculates total_tokens" do
      context = Context.new("Hello", [])
      usage = %{input_tokens: 100}

      context = Context.add_token_usage(context, usage)

      cumulative = Context.get_cumulative_tokens(context)
      assert cumulative.input_tokens == 100
      assert cumulative.output_tokens == 0
      assert cumulative.total_tokens == 100
    end
  end

  describe "get_cumulative_tokens/1" do
    test "returns zero tokens for new context" do
      context = Context.new("Hello", [])

      cumulative = Context.get_cumulative_tokens(context)
      assert cumulative.input_tokens == 0
      assert cumulative.output_tokens == 0
      assert cumulative.total_tokens == 0
    end

    test "returns cumulative tokens after usage added" do
      context = Context.new("Hello", [])
      usage = %{input_tokens: 200, output_tokens: 100, total_tokens: 300}

      context = Context.add_token_usage(context, usage)

      cumulative = Context.get_cumulative_tokens(context)
      assert cumulative.input_tokens == 200
      assert cumulative.output_tokens == 100
      assert cumulative.total_tokens == 300
    end
  end
end
