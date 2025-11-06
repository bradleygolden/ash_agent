defmodule AshAgent.ToolRegistryTest do
  use ExUnit.Case, async: false

  alias AshAgent.ToolRegistry
  alias AshAgent.Tools.Function

  setup do
    ToolRegistry.start_link([])
    ToolRegistry.clear_all()
    :ok
  end

  describe "register_tool/3" do
    test "registers a tool for a domain" do
      tool =
        Function.new(
          name: :test_tool,
          description: "Test tool",
          function: fn _args -> {:ok, %{result: "test"}} end
        )

      assert :ok = ToolRegistry.register_tool(MyDomain, :test_tool, tool)
      assert ToolRegistry.get_tool(MyDomain, :test_tool) == tool
    end

    test "registers multiple tools for the same domain" do
      tool1 =
        Function.new(
          name: :tool1,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool2,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(MyDomain, :tool1, tool1)
      ToolRegistry.register_tool(MyDomain, :tool2, tool2)

      assert ToolRegistry.get_tool(MyDomain, :tool1) == tool1
      assert ToolRegistry.get_tool(MyDomain, :tool2) == tool2
    end

    test "registers tools for different domains independently" do
      tool1 =
        Function.new(
          name: :tool1,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool2,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(Domain1, :shared_name, tool1)
      ToolRegistry.register_tool(Domain2, :shared_name, tool2)

      assert ToolRegistry.get_tool(Domain1, :shared_name) == tool1
      assert ToolRegistry.get_tool(Domain2, :shared_name) == tool2
    end

    test "overwrites existing tool with same name in same domain" do
      tool1 =
        Function.new(
          name: :tool,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(MyDomain, :tool, tool1)
      ToolRegistry.register_tool(MyDomain, :tool, tool2)

      assert ToolRegistry.get_tool(MyDomain, :tool) == tool2
    end
  end

  describe "get_tool/2" do
    test "returns nil for non-existent tool" do
      assert ToolRegistry.get_tool(MyDomain, :nonexistent) == nil
    end

    test "returns nil for non-existent domain" do
      assert ToolRegistry.get_tool(NonExistentDomain, :tool) == nil
    end

    test "retrieves registered tool" do
      tool =
        Function.new(
          name: :test_tool,
          description: "Test tool",
          function: fn _args -> {:ok, %{result: "test"}} end
        )

      ToolRegistry.register_tool(MyDomain, :test_tool, tool)

      assert ToolRegistry.get_tool(MyDomain, :test_tool) == tool
    end
  end

  describe "list_tools/1" do
    test "returns empty map for domain with no tools" do
      assert ToolRegistry.list_tools(EmptyDomain) == %{}
    end

    test "returns all tools for a domain" do
      tool1 =
        Function.new(
          name: :tool1,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool2,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(MyDomain, :tool1, tool1)
      ToolRegistry.register_tool(MyDomain, :tool2, tool2)

      tools = ToolRegistry.list_tools(MyDomain)

      assert map_size(tools) == 2
      assert tools[:tool1] == tool1
      assert tools[:tool2] == tool2
    end

    test "returns only tools for the specified domain" do
      tool1 =
        Function.new(
          name: :tool1,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool2,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(Domain1, :tool1, tool1)
      ToolRegistry.register_tool(Domain2, :tool2, tool2)

      tools1 = ToolRegistry.list_tools(Domain1)
      tools2 = ToolRegistry.list_tools(Domain2)

      assert map_size(tools1) == 1
      assert tools1[:tool1] == tool1

      assert map_size(tools2) == 1
      assert tools2[:tool2] == tool2
    end
  end

  describe "unregister_tool/2" do
    test "removes a tool from a domain" do
      tool =
        Function.new(
          name: :test_tool,
          description: "Test tool",
          function: fn _args -> {:ok, %{result: "test"}} end
        )

      ToolRegistry.register_tool(MyDomain, :test_tool, tool)
      assert ToolRegistry.get_tool(MyDomain, :test_tool) == tool

      ToolRegistry.unregister_tool(MyDomain, :test_tool)
      assert ToolRegistry.get_tool(MyDomain, :test_tool) == nil
    end

    test "does not affect other tools in the same domain" do
      tool1 =
        Function.new(
          name: :tool1,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool2,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(MyDomain, :tool1, tool1)
      ToolRegistry.register_tool(MyDomain, :tool2, tool2)

      ToolRegistry.unregister_tool(MyDomain, :tool1)

      assert ToolRegistry.get_tool(MyDomain, :tool1) == nil
      assert ToolRegistry.get_tool(MyDomain, :tool2) == tool2
    end

    test "does not affect tools in other domains" do
      tool1 =
        Function.new(
          name: :tool,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(Domain1, :tool, tool1)
      ToolRegistry.register_tool(Domain2, :tool, tool2)

      ToolRegistry.unregister_tool(Domain1, :tool)

      assert ToolRegistry.get_tool(Domain1, :tool) == nil
      assert ToolRegistry.get_tool(Domain2, :tool) == tool2
    end

    test "returns :ok even if tool doesn't exist" do
      assert :ok = ToolRegistry.unregister_tool(MyDomain, :nonexistent)
    end

    test "removes domain from registry when last tool is unregistered" do
      tool =
        Function.new(
          name: :tool,
          description: "Tool",
          function: fn _args -> {:ok, %{result: "test"}} end
        )

      ToolRegistry.register_tool(MyDomain, :tool, tool)
      ToolRegistry.unregister_tool(MyDomain, :tool)

      assert ToolRegistry.list_tools(MyDomain) == %{}
    end
  end

  describe "clear_domain/1" do
    test "removes all tools for a domain" do
      tool1 =
        Function.new(
          name: :tool1,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool2,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(MyDomain, :tool1, tool1)
      ToolRegistry.register_tool(MyDomain, :tool2, tool2)

      ToolRegistry.clear_domain(MyDomain)

      assert ToolRegistry.list_tools(MyDomain) == %{}
    end

    test "does not affect other domains" do
      tool1 =
        Function.new(
          name: :tool1,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool2,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(Domain1, :tool1, tool1)
      ToolRegistry.register_tool(Domain2, :tool2, tool2)

      ToolRegistry.clear_domain(Domain1)

      assert ToolRegistry.list_tools(Domain1) == %{}
      assert ToolRegistry.get_tool(Domain2, :tool2) == tool2
    end

    test "returns :ok even if domain doesn't exist" do
      assert :ok = ToolRegistry.clear_domain(NonExistentDomain)
    end
  end

  describe "clear_all/0" do
    test "removes all tools from all domains" do
      tool1 =
        Function.new(
          name: :tool1,
          description: "Tool 1",
          function: fn _args -> {:ok, %{result: "1"}} end
        )

      tool2 =
        Function.new(
          name: :tool2,
          description: "Tool 2",
          function: fn _args -> {:ok, %{result: "2"}} end
        )

      ToolRegistry.register_tool(Domain1, :tool1, tool1)
      ToolRegistry.register_tool(Domain2, :tool2, tool2)

      ToolRegistry.clear_all()

      assert ToolRegistry.list_tools(Domain1) == %{}
      assert ToolRegistry.list_tools(Domain2) == %{}
    end
  end
end
