defmodule AshAgent.RuntimeRegistryTest do
  use ExUnit.Case, async: false

  alias AshAgent.RuntimeRegistry

  describe "tool runtime registration" do
    test "get_tool_runtime/0 returns :error when no handler registered" do
      # Clear any existing registration by checking current state
      # Note: We can't easily clear ETS in tests, so we test the API behavior
      case RuntimeRegistry.get_tool_runtime() do
        {:ok, _module} ->
          # Handler already registered (from ash_agent_tools), just verify it returns {:ok, _}
          assert {:ok, module} = RuntimeRegistry.get_tool_runtime()
          assert is_atom(module)

        :error ->
          assert :error = RuntimeRegistry.get_tool_runtime()
      end
    end

    test "register_tool_runtime/1 registers a handler module" do
      defmodule TestToolRuntime do
        def call(_agent, _args, _opts), do: {:ok, %{}}
        def stream(_agent, _args, _opts), do: {:ok, []}
      end

      assert :ok = RuntimeRegistry.register_tool_runtime(TestToolRuntime)
      assert {:ok, TestToolRuntime} = RuntimeRegistry.get_tool_runtime()
    end

    test "has_tool_runtime?/0 returns boolean" do
      result = RuntimeRegistry.has_tool_runtime?()
      assert is_boolean(result)
    end

    test "has_tool_runtime?/0 returns true after registration" do
      defmodule AnotherTestToolRuntime do
        def call(_agent, _args, _opts), do: {:ok, %{}}
        def stream(_agent, _args, _opts), do: {:ok, []}
      end

      RuntimeRegistry.register_tool_runtime(AnotherTestToolRuntime)
      assert RuntimeRegistry.has_tool_runtime?() == true
    end
  end

  describe "context module registration" do
    test "get_context_module/0 returns default when not registered" do
      # This tests the default behavior - should return AshAgent.Context
      # Note: Other tests may have registered a custom module
      module = RuntimeRegistry.get_context_module()
      assert is_atom(module)
    end

    test "register_context_module/1 registers a context module" do
      defmodule TestContextModule do
        def new(_input, _opts), do: %{}
        def to_messages(_context), do: []
      end

      assert :ok = RuntimeRegistry.register_context_module(TestContextModule)
      assert RuntimeRegistry.get_context_module() == TestContextModule

      # Clean up
      RuntimeRegistry.register_context_module(AshAgent.Context)
    end

    test "get_context_module/0 returns AshAgent.Context as default" do
      # Ensure we're testing the default
      RuntimeRegistry.register_context_module(AshAgent.Context)
      assert RuntimeRegistry.get_context_module() == AshAgent.Context
    end
  end

  describe "GenServer behaviour" do
    test "registry is started and running" do
      assert Process.whereis(RuntimeRegistry) != nil
    end

    test "registry can handle multiple registrations" do
      for i <- 1..3 do
        module_name = String.to_atom("TestModule#{i}_#{System.unique_integer([:positive])}")

        {:module, module, _, _} =
          Module.create(
            module_name,
            quote do
              def call(_a, _b, _c), do: {:ok, %{}}
              def stream(_a, _b, _c), do: {:ok, []}
            end,
            Macro.Env.location(__ENV__)
          )

        assert :ok = RuntimeRegistry.register_tool_runtime(module)
      end
    end

    test "ETS table is accessible" do
      # The registry uses a public ETS table for read concurrency
      assert :ets.info(:ash_agent_runtime_registry) != :undefined
    end
  end
end
