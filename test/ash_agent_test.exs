defmodule AshAgentTest do
  use ExUnit.Case
  doctest AshAgent

  describe "extension modules" do
    test "AshAgent.Resource module exists" do
      assert Code.ensure_loaded?(AshAgent.Resource)
    end

    test "AshAgent.Domain module exists" do
      assert Code.ensure_loaded?(AshAgent.Domain)
    end

    test "AshAgent.Info module exists" do
      assert Code.ensure_loaded?(AshAgent.Info)
    end
  end
end
