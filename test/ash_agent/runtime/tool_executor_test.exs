defmodule AshAgent.Runtime.ToolExecutorTest do
  use ExUnit.Case, async: true

  alias AshAgent.{Conversation, Runtime.ToolExecutor, TestDomain}

  defmodule TestAgent do
    use Ash.Resource, domain: TestDomain, extensions: [AshAgent.Resource]
  end


  defmodule TestResource do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false
    end

    actions do
      defaults [:read, :create]
      default_accept [:name]
    end
  end

  describe "execute_tools/3" do
    test "executes function tools" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [domain: TestDomain])

      tool_definitions = [
        %{
          name: :greet,
          description: "Greet someone",
          function: fn args, _context -> {:ok, %{greeting: "Hello, #{args.name}!"}} end,
          parameters: [%{name: :name, type: :string, required: true}]
        }
      ]

      tool_calls = [
        %{id: "call_1", name: :greet, arguments: %{name: "Alice"}}
      ]

      results = ToolExecutor.execute_tools(tool_calls, tool_definitions, conversation)

      assert length(results) == 1
      {id, {status, result}} = hd(results)
      assert id == "call_1"
      assert status == :ok
      assert result.greeting == "Hello, Alice!"
    end

    test "executes Ash action tools" do
      {:ok, user} =
        TestResource
        |> Ash.Changeset.for_create(:create, %{name: "TestUser"})
        |> Ash.create()

      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [domain: TestDomain])

      tool_definitions = [
        %{
          name: :get_user,
          description: "Get user by name",
          action: {TestResource, :read},
          parameters: []
        }
      ]

      tool_calls = [
        %{id: "call_1", name: :get_user, arguments: %{}}
      ]

      results = ToolExecutor.execute_tools(tool_calls, tool_definitions, conversation)

      assert length(results) == 1
      {id, {status, result}} = hd(results)
      assert id == "call_1"
      assert status == :ok
      assert is_list(result)
      assert length(result) >= 1
      assert hd(result).name == user.name
    end

    test "handles missing tools" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [domain: TestDomain])

      tool_definitions = []

      tool_calls = [
        %{id: "call_1", name: :nonexistent, arguments: %{}}
      ]

      results = ToolExecutor.execute_tools(tool_calls, tool_definitions, conversation)

      assert length(results) == 1
      {id, {status, reason}} = hd(results)
      assert id == "call_1"
      assert status == :error
      assert reason =~ "not found"
    end

    test "handles tool execution errors" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [domain: TestDomain])

      tool_definitions = [
        %{
          name: :error_tool,
          description: "Tool that errors",
          function: fn _args, _context -> {:error, "Something went wrong"} end,
          parameters: []
        }
      ]

      tool_calls = [
        %{id: "call_1", name: :error_tool, arguments: %{}}
      ]

      results = ToolExecutor.execute_tools(tool_calls, tool_definitions, conversation)

      assert length(results) == 1
      {id, {status, reason}} = hd(results)
      assert id == "call_1"
      assert status == :error
      assert reason == "Something went wrong"
    end

    test "validates required parameters" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [domain: TestDomain])

      tool_definitions = [
        %{
          name: :needs_param,
          description: "Needs a parameter",
          function: fn args, _context -> {:ok, args} end,
          parameters: [%{name: :required_field, type: :string, required: true}]
        }
      ]

      tool_calls = [
        %{id: "call_1", name: :needs_param, arguments: %{}}
      ]

      results = ToolExecutor.execute_tools(tool_calls, tool_definitions, conversation)

      assert length(results) == 1
      {id, {status, reason}} = hd(results)
      assert id == "call_1"
      assert status == :error
      assert reason =~ "Missing required parameters"
    end

    test "handles multiple tool calls" do
      conversation = Conversation.new(TestAgent, %{message: "Hello"}, [domain: TestDomain])

      tool_definitions = [
        %{
          name: :tool1,
          description: "First tool",
          function: fn _args, _context -> {:ok, %{result: 1}} end,
          parameters: []
        },
        %{
          name: :tool2,
          description: "Second tool",
          function: fn _args, _context -> {:ok, %{result: 2}} end,
          parameters: []
        }
      ]

      tool_calls = [
        %{id: "call_1", name: :tool1, arguments: %{}},
        %{id: "call_2", name: :tool2, arguments: %{}}
      ]

      results = ToolExecutor.execute_tools(tool_calls, tool_definitions, conversation)

      assert length(results) == 2
      assert {"call_1", {:ok, %{result: 1}}} in results
      assert {"call_2", {:ok, %{result: 2}}} in results
    end
  end
end

