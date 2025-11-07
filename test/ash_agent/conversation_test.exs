defmodule AshAgent.ConversationTest do
  use ExUnit.Case, async: true

  alias AshAgent.{Conversation, TestDomain}

  defmodule TestAgent do
    use Ash.Resource, domain: TestDomain, extensions: [AshAgent.Resource]
  end

  describe "new/3" do
    test "creates a new conversation with initial user message" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])

      assert conversation.agent == TestAgent
      assert conversation.iteration == 0
      assert conversation.max_iterations == 10
      assert length(conversation.messages) == 1

      [message] = conversation.messages
      assert message.role == :user
      assert message.content == "Hello"
    end

    test "creates conversation with options" do
      conversation =
        Conversation.new(TestAgent, %{message: "Hi"},
          domain: TestDomain,
          actor: %{id: 1},
          tenant: "org-1",
          max_iterations: 5
        )

      assert conversation.domain == TestDomain
      assert conversation.actor == %{id: 1}
      assert conversation.tenant == "org-1"
      assert conversation.max_iterations == 5
    end

    test "handles map input without message key" do
      conversation = Conversation.new(TestAgent, %{data: "test"}, [])

      [message] = conversation.messages
      assert message.role == :user
      assert is_binary(message.content)
    end
  end

  describe "add_assistant_message/3" do
    test "adds assistant message to conversation" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])
      conversation = Conversation.add_assistant_message(conversation, "Hi there!")

      assert conversation.iteration == 1
      assert length(conversation.messages) == 2

      [_, message] = conversation.messages
      assert message.role == :assistant
      assert message.content == "Hi there!"
      assert message.tool_calls == nil
    end

    test "adds assistant message with tool calls" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])
      tool_calls = [%{id: "call_1", name: "get_weather", arguments: %{city: "NYC"}}]

      conversation = Conversation.add_assistant_message(conversation, "Let me check", tool_calls)

      assert conversation.iteration == 1
      assert length(conversation.messages) == 2

      [_, message] = conversation.messages
      assert message.role == :assistant
      assert message.content == "Let me check"
      assert message.tool_calls == tool_calls
    end
  end

  describe "add_tool_results/2" do
    test "adds tool results to conversation" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])
      conversation = Conversation.add_assistant_message(conversation, "Checking", [
        %{id: "call_1", name: "get_weather", arguments: %{}}
      ])

      results = [
        {"call_1", {:ok, %{temperature: 72}}}
      ]

      conversation = Conversation.add_tool_results(conversation, results)

      assert length(conversation.messages) == 3

      [_, _, result_message] = conversation.messages
      assert result_message.role == :user
      assert is_list(result_message.content)
      assert length(result_message.content) == 1

      [content_part] = result_message.content
      assert content_part.type == :tool_result
      assert content_part.tool_use_id == "call_1"
      assert is_binary(content_part.content)
    end

    test "handles tool errors" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])
      conversation = Conversation.add_assistant_message(conversation, "Checking", [
        %{id: "call_1", name: "get_weather", arguments: %{}}
      ])

      results = [
        {"call_1", {:error, "API unavailable"}}
      ]

      conversation = Conversation.add_tool_results(conversation, results)

      [_, _, result_message] = conversation.messages
      [content_part] = result_message.content
      assert content_part.type == :tool_result
      assert is_binary(content_part.content)
    end
  end

  describe "exceeded_max_iterations?/1" do
    test "returns false when under max iterations" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, max_iterations: 5)

      refute Conversation.exceeded_max_iterations?(conversation)
    end

    test "returns true when at max iterations" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, max_iterations: 2)

      conversation = Conversation.add_assistant_message(conversation, "Response 1")
      conversation = Conversation.add_assistant_message(conversation, "Response 2")

      assert Conversation.exceeded_max_iterations?(conversation)
    end
  end

  describe "extract_tool_calls/1" do
    test "extracts tool calls from last assistant message" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])
      tool_calls = [%{id: "call_1", name: "get_weather", arguments: %{}}]

      conversation = Conversation.add_assistant_message(conversation, "Checking", tool_calls)

      assert Conversation.extract_tool_calls(conversation) == tool_calls
    end

    test "returns empty list when no tool calls" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])
      conversation = Conversation.add_assistant_message(conversation, "No tools")

      assert Conversation.extract_tool_calls(conversation) == []
    end

    test "returns empty list when last message is not assistant" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])

      assert Conversation.extract_tool_calls(conversation) == []
    end
  end

  describe "to_messages/1" do
    test "converts conversation to provider message format" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])
      conversation = Conversation.add_assistant_message(conversation, "Hi there!")

      messages = Conversation.to_messages(conversation)

      assert length(messages) == 2
      assert hd(messages).role == "user"
      assert List.last(messages).role == "assistant"
    end

    test "formats tool calls in messages" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])
      tool_calls = [%{id: "call_1", name: "get_weather", arguments: %{city: "NYC"}}]

      conversation = Conversation.add_assistant_message(conversation, "Checking", tool_calls)

      messages = Conversation.to_messages(conversation)
      assistant_message = List.last(messages)

      assert assistant_message.role == :assistant
      assert is_list(assistant_message.tool_calls)
      assert length(assistant_message.tool_calls) == 1

      [tool_call] = assistant_message.tool_calls
      assert tool_call.id == "call_1"
      assert tool_call.function.name == "get_weather"
    end

    test "formats tool results in messages" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [])
      conversation = Conversation.add_assistant_message(conversation, "Checking", [
        %{id: "call_1", name: "get_weather", arguments: %{}}
      ])

      results = [{"call_1", {:ok, %{temperature: 72}}}]
      conversation = Conversation.add_tool_results(conversation, results)

      messages = Conversation.to_messages(conversation)
      assert length(messages) == 3

      result_message = Enum.at(messages, 2)
      assert result_message.role == :user
      assert is_list(result_message.content)
    end
  end
end

