defmodule AshAgent.ContextTest do
  use ExUnit.Case, async: true

  alias AshAgent.Context
  alias AshAgent.Message

  describe "new/2" do
    test "creates a new context from list of messages" do
      messages = [
        Message.system("You are helpful"),
        Message.user("Hello")
      ]

      context = Context.new(messages)

      assert %Context{messages: msgs} = context
      assert length(msgs) == 2
    end

    test "flattens nested contexts" do
      inner = Context.new([Message.user("Hello")])

      context =
        Context.new([
          Message.system("System"),
          inner,
          Message.user("World")
        ])

      assert length(context.messages) == 3
    end

    test "accepts metadata option" do
      context = Context.new([Message.user("Hello")], metadata: %{key: "value"})

      assert context.metadata.key == "value"
    end
  end

  describe "to_provider_format/1" do
    test "extracts system prompt and conversation" do
      context =
        Context.new([
          Message.system("Be helpful"),
          Message.user(%{message: "Hello"})
        ])

      {system_prompt, conversation} = Context.to_provider_format(context)

      assert system_prompt == "Be helpful"
      assert length(conversation) == 1
      assert hd(conversation).role == "user"
    end

    test "returns nil for system prompt when not present" do
      context = Context.new([Message.user("Hello")])

      {system_prompt, conversation} = Context.to_provider_format(context)

      assert system_prompt == nil
      assert length(conversation) == 1
    end
  end

  describe "messages/1" do
    test "returns the messages list" do
      messages = [Message.user("Hello")]
      context = Context.new(messages)

      assert Context.messages(context) == messages
    end
  end

  describe "add_assistant_message/2" do
    test "adds assistant message to context" do
      context = Context.new([Message.user("Hello")])
      context = Context.add_assistant_message(context, "Hi there!")

      assert length(context.messages) == 2
      assert List.last(context.messages).role == :assistant
      assert List.last(context.messages).content == "Hi there!"
    end
  end

  describe "add_user_message/2" do
    test "adds user message to context" do
      context = Context.new([Message.system("Be helpful")])
      context = Context.add_user_message(context, "Hello")

      assert length(context.messages) == 2
      assert List.last(context.messages).role == :user
    end
  end

  describe "put_metadata/3" do
    test "adds metadata to context" do
      context = Context.new([Message.user("Hello")])
      context = Context.put_metadata(context, :key, "value")

      assert context.metadata.key == "value"
    end

    test "overwrites existing metadata key" do
      context = Context.new([Message.user("Hello")], metadata: %{key: "old"})
      context = Context.put_metadata(context, :key, "new")

      assert context.metadata.key == "new"
    end
  end

  describe "get_metadata/3" do
    test "retrieves metadata value" do
      context = Context.new([Message.user("Hello")], metadata: %{key: "value"})

      assert Context.get_metadata(context, :key) == "value"
    end

    test "returns default when key not found" do
      context = Context.new([Message.user("Hello")])

      assert Context.get_metadata(context, :missing, "default") == "default"
    end

    test "returns nil as default when key not found" do
      context = Context.new([Message.user("Hello")])

      assert Context.get_metadata(context, :missing) == nil
    end
  end
end
