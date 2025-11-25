defmodule AshAgent.ConfigTest do
  use ExUnit.Case, async: false

  alias AshAgent.Config
  alias AshAgent.RuntimeRegistry

  describe "context_module/0" do
    test "returns AshAgent.Context when no custom context registered" do
      RuntimeRegistry.register_context_module(AshAgent.Context)
      assert Config.context_module() == AshAgent.Context
    end

    test "returns registered context module after registration" do
      # Register a custom context module
      defmodule TestCustomContext do
        def new(_input, _opts), do: %{}
      end

      RuntimeRegistry.register_context_module(TestCustomContext)

      assert Config.context_module() == TestCustomContext

      # Clean up by re-registering default
      RuntimeRegistry.register_context_module(AshAgent.Context)
    end
  end
end
