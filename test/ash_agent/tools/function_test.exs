defmodule AshAgent.Tools.FunctionTest do
  use ExUnit.Case, async: true

  alias AshAgent.Tools.Function

  describe "new/1" do
    test "creates a function tool with required fields" do
      tool =
        Function.new(
          name: :test_tool,
          description: "A test tool",
          function: fn args, _context -> {:ok, args} end,
          parameters: []
        )

      assert tool.name == :test_tool
      assert tool.description == "A test tool"
      assert is_function(tool.function)
      assert tool.parameters == []
    end

    test "raises when required fields are missing" do
      assert_raise KeyError, fn ->
        Function.new(description: "Missing name")
      end
    end
  end

  describe "execute/2" do
    test "executes an anonymous function with 2 arity" do
      tool =
        Function.new(
          name: :greet,
          description: "Greet someone",
          function: fn args, _context -> {:ok, %{greeting: "Hello, #{args.name}!"}} end,
          parameters: [%{name: :name, type: :string, required: true}]
        )

      context = %{
        tool: tool,
        agent: TestAgent,
        domain: TestDomain,
        actor: nil,
        tenant: nil
      }

      assert {:ok, %{greeting: "Hello, Ralph!"}} =
               Function.execute(%{name: "Ralph"}, context)
    end

    test "executes an anonymous function with 1 arity" do
      tool =
        Function.new(
          name: :double,
          description: "Double a number",
          function: fn args -> {:ok, %{result: args.number * 2}} end,
          parameters: [%{name: :number, type: :integer, required: true}]
        )

      context = %{
        tool: tool,
        agent: TestAgent,
        domain: TestDomain,
        actor: nil,
        tenant: nil
      }

      assert {:ok, %{result: 10}} = Function.execute(%{number: 5}, context)
    end

    test "executes an MFA tuple with context" do
      defmodule TestModule do
        def test_function(args, _context) do
          {:ok, %{value: args.input}}
        end
      end

      tool =
        Function.new(
          name: :mfa_tool,
          description: "Test MFA",
          function: {TestModule, :test_function, []},
          parameters: [%{name: :input, type: :string, required: true}]
        )

      context = %{
        tool: tool,
        agent: TestAgent,
        domain: TestDomain,
        actor: nil,
        tenant: nil
      }

      assert {:ok, %{value: "test"}} = Function.execute(%{input: "test"}, context)
    end

    test "validates required parameters" do
      tool =
        Function.new(
          name: :needs_param,
          description: "Needs a parameter",
          function: fn args, _context -> {:ok, args} end,
          parameters: [%{name: :required_field, type: :string, required: true}]
        )

      context = %{
        tool: tool,
        agent: TestAgent,
        domain: TestDomain,
        actor: nil,
        tenant: nil
      }

      assert {:error, "Missing required parameters: [:required_field]"} =
               Function.execute(%{}, context)
    end

    test "handles string keys in arguments" do
      tool =
        Function.new(
          name: :string_keys,
          description: "Handles string keys",
          function: fn args, _context -> {:ok, %{got: args.name}} end,
          parameters: [%{name: :name, type: :string, required: true}]
        )

      context = %{
        tool: tool,
        agent: TestAgent,
        domain: TestDomain,
        actor: nil,
        tenant: nil
      }

      assert {:ok, %{got: "Ralph"}} = Function.execute(%{"name" => "Ralph"}, context)
    end

    test "normalizes non-tuple results" do
      tool =
        Function.new(
          name: :raw_return,
          description: "Returns raw value",
          function: fn _args, _context -> "raw result" end,
          parameters: []
        )

      context = %{
        tool: tool,
        agent: TestAgent,
        domain: TestDomain,
        actor: nil,
        tenant: nil
      }

      assert {:ok, %{result: "raw result"}} = Function.execute(%{}, context)
    end

    test "normalizes map results" do
      tool =
        Function.new(
          name: :map_return,
          description: "Returns map",
          function: fn _args, _context -> %{custom: "data"} end,
          parameters: []
        )

      context = %{
        tool: tool,
        agent: TestAgent,
        domain: TestDomain,
        actor: nil,
        tenant: nil
      }

      assert {:ok, %{custom: "data"}} = Function.execute(%{}, context)
    end

    test "handles function errors" do
      tool =
        Function.new(
          name: :error_tool,
          description: "Raises error",
          function: fn _args, _context -> raise "Something went wrong" end,
          parameters: []
        )

      context = %{
        tool: tool,
        agent: TestAgent,
        domain: TestDomain,
        actor: nil,
        tenant: nil
      }

      assert {:error, "Something went wrong"} = Function.execute(%{}, context)
    end

    test "handles explicit error tuples" do
      tool =
        Function.new(
          name: :error_tuple,
          description: "Returns error tuple",
          function: fn _args, _context -> {:error, "Failed"} end,
          parameters: []
        )

      context = %{
        tool: tool,
        agent: TestAgent,
        domain: TestDomain,
        actor: nil,
        tenant: nil
      }

      assert {:error, "Failed"} = Function.execute(%{}, context)
    end
  end

  describe "behavior implementation" do
    test "implements name/0" do
      assert Function.name() == :function
    end

    test "implements description/0" do
      assert is_binary(Function.description())
    end

    test "implements schema/0" do
      schema = Function.schema()
      assert schema.name == "function"
      assert is_binary(schema.description)
      assert schema.parameters.type == :object
    end
  end
end
