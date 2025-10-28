defmodule AshAgentTest do
  use ExUnit.Case
  doctest AshAgent

  test "greets the world" do
    assert AshAgent.hello() == :world
  end
end
