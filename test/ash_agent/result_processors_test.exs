defmodule AshAgent.ResultProcessorsTest do
  use ExUnit.Case, async: true

  doctest AshAgent.ResultProcessors

  alias AshAgent.ResultProcessors

  describe "large?/2" do
    test "returns false for small data" do
      assert ResultProcessors.large?("small", 1000) == false
    end

    test "returns true for large data" do
      large = String.duplicate("x", 2000)
      assert ResultProcessors.large?(large, 1000) == true
    end

    test "works with lists" do
      small_list = [1, 2, 3]
      large_list = Enum.to_list(1..1000)

      assert ResultProcessors.large?(small_list, 100) == false
      assert ResultProcessors.large?(large_list, 100) == true
    end

    test "works with maps" do
      small_map = %{a: 1, b: 2}
      large_map = Map.new(1..1000, fn i -> {i, i} end)

      assert ResultProcessors.large?(small_map, 100) == false
      assert ResultProcessors.large?(large_map, 100) == true
    end
  end

  describe "estimate_size/1" do
    test "estimates binary size" do
      binary = "hello"
      assert ResultProcessors.estimate_size(binary) == 5
    end

    test "estimates list size" do
      list = [1, 2, 3, 4, 5]
      assert ResultProcessors.estimate_size(list) == 5
    end

    test "estimates map size" do
      map = %{a: 1, b: 2, c: 3}
      assert ResultProcessors.estimate_size(map) == 3
    end

    test "returns 0 for other types" do
      assert ResultProcessors.estimate_size(123) == 0
      assert ResultProcessors.estimate_size(:atom) == 0
      assert ResultProcessors.estimate_size({:tuple, 1}) == 0
    end
  end

  describe "preserve_structure/2" do
    test "transforms successful result data" do
      input = {"tool", {:ok, "hello"}}
      transform_fn = &String.upcase/1

      assert ResultProcessors.preserve_structure(input, transform_fn) ==
               {"tool", {:ok, "HELLO"}}
    end

    test "preserves error results unchanged" do
      input = {"tool", {:error, "oops"}}
      transform_fn = &String.upcase/1

      assert ResultProcessors.preserve_structure(input, transform_fn) ==
               {"tool", {:error, "oops"}}
    end

    test "transform function is not called for errors" do
      input = {"tool", {:error, "oops"}}

      transform_fn = fn _ ->
        raise "Should not be called!"
      end

      assert ResultProcessors.preserve_structure(input, transform_fn) ==
               {"tool", {:error, "oops"}}
    end
  end
end
