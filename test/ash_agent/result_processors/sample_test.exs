defmodule AshAgent.ResultProcessors.SampleTest do
  use ExUnit.Case, async: true

  alias AshAgent.ResultProcessors.Sample

  describe "process/2 with :first strategy" do
    test "samples first N items from large list" do
      large_list = Enum.to_list(1..100)
      results = [{"query", {:ok, large_list}}]

      sampled = Sample.process(results, sample_size: 5)

      assert [{"query", {:ok, result}}] = sampled
      assert %{items: items, total_count: 100, sampled: true, strategy: :first} = result
      assert items == [1, 2, 3, 4, 5]
    end

    test "preserves list when smaller than sample_size" do
      small_list = [1, 2, 3]
      results = [{"tool", {:ok, small_list}}]

      sampled = Sample.process(results, sample_size: 5)

      assert [{"tool", {:ok, ^small_list}}] = sampled
    end

    test "handles empty list" do
      results = [{"tool", {:ok, []}}]

      sampled = Sample.process(results, sample_size: 5)

      assert [{"tool", {:ok, []}}] = sampled
    end

    test "preserves order of items" do
      list = [10, 20, 30, 40, 50, 60]
      results = [{"tool", {:ok, list}}]

      sampled = Sample.process(results, sample_size: 3)

      assert [{"tool", {:ok, result}}] = sampled
      assert %{items: items} = result
      assert items == [10, 20, 30]
    end

    test "includes total_count metadata" do
      list = Enum.to_list(1..50)
      results = [{"tool", {:ok, list}}]

      sampled = Sample.process(results, sample_size: 10)

      assert [{"tool", {:ok, result}}] = sampled
      assert %{total_count: 50, sampled: true} = result
    end
  end

  describe "process/2 with :random strategy" do
    test "samples random items from list" do
      large_list = Enum.to_list(1..100)
      results = [{"query", {:ok, large_list}}]

      sampled = Sample.process(results, sample_size: 5, strategy: :random)

      assert [{"query", {:ok, result}}] = sampled
      assert %{items: items, total_count: 100, sampled: true, strategy: :random} = result
      assert length(items) == 5
      assert Enum.all?(items, fn item -> item in large_list end)
    end

    test "preserves list when smaller than sample_size" do
      small_list = [1, 2, 3]
      results = [{"tool", {:ok, small_list}}]

      sampled = Sample.process(results, sample_size: 5, strategy: :random)

      assert [{"tool", {:ok, ^small_list}}] = sampled
    end
  end

  describe "process/2 with :distributed strategy" do
    test "samples evenly distributed items" do
      large_list = Enum.to_list(1..100)
      results = [{"query", {:ok, large_list}}]

      sampled = Sample.process(results, sample_size: 5, strategy: :distributed)

      assert [{"query", {:ok, result}}] = sampled
      assert %{items: items, total_count: 100, sampled: true, strategy: :distributed} = result
      assert length(items) == 5
      assert Enum.all?(items, fn item -> item in large_list end)
    end

    test "preserves list when smaller than sample_size" do
      small_list = [1, 2, 3]
      results = [{"tool", {:ok, small_list}}]

      sampled = Sample.process(results, sample_size: 5, strategy: :distributed)

      assert [{"tool", {:ok, ^small_list}}] = sampled
    end
  end

  describe "process/2 with non-list data" do
    test "passes through binary data unchanged" do
      results = [{"tool", {:ok, "not a list"}}]

      sampled = Sample.process(results)

      assert [{"tool", {:ok, "not a list"}}] = sampled
    end

    test "passes through map data unchanged" do
      map_data = %{key: "value"}
      results = [{"tool", {:ok, map_data}}]

      sampled = Sample.process(results)

      assert [{"tool", {:ok, ^map_data}}] = sampled
    end

    test "passes through integer data unchanged" do
      results = [{"tool", {:ok, 42}}]

      sampled = Sample.process(results)

      assert [{"tool", {:ok, 42}}] = sampled
    end
  end

  describe "process/2 with error results" do
    test "preserves error results unchanged" do
      results = [{"tool", {:error, "oops"}}]

      sampled = Sample.process(results)

      assert [{"tool", {:error, "oops"}}] = sampled
    end

    test "preserves error in batch with success" do
      results = [
        {"tool1", {:ok, Enum.to_list(1..100)}},
        {"tool2", {:error, "failed"}},
        {"tool3", {:ok, Enum.to_list(1..50)}}
      ]

      sampled = Sample.process(results, sample_size: 3)

      assert [
               {"tool1", {:ok, result1}},
               {"tool2", {:error, "failed"}},
               {"tool3", {:ok, result3}}
             ] = sampled

      assert %{items: items1} = result1
      assert length(items1) == 3
      assert %{items: items3} = result3
      assert length(items3) == 3
    end
  end

  describe "process/2 with options" do
    test "uses default sample_size when not specified" do
      list = Enum.to_list(1..100)
      results = [{"tool", {:ok, list}}]

      sampled = Sample.process(results)

      assert [{"tool", {:ok, result}}] = sampled
      assert %{items: items} = result
      assert length(items) == 5
    end

    test "uses custom sample_size" do
      list = Enum.to_list(1..100)
      results = [{"tool", {:ok, list}}]

      sampled = Sample.process(results, sample_size: 10)

      assert [{"tool", {:ok, result}}] = sampled
      assert %{items: items} = result
      assert length(items) == 10
    end

    test "uses default :first strategy when not specified" do
      list = Enum.to_list(1..100)
      results = [{"tool", {:ok, list}}]

      sampled = Sample.process(results, sample_size: 3)

      assert [{"tool", {:ok, result}}] = sampled
      assert %{strategy: :first} = result
    end
  end

  describe "process/2 with edge cases" do
    test "handles empty results list" do
      sampled = Sample.process([])

      assert sampled == []
    end

    test "handles multiple results in batch" do
      results = [
        {"tool1", {:ok, Enum.to_list(1..100)}},
        {"tool2", {:ok, Enum.to_list(1..50)}},
        {"tool3", {:ok, Enum.to_list(1..25)}}
      ]

      sampled = Sample.process(results, sample_size: 3)

      assert [
               {"tool1", {:ok, result1}},
               {"tool2", {:ok, result2}},
               {"tool3", {:ok, result3}}
             ] = sampled

      assert %{items: items1} = result1
      assert length(items1) == 3
      assert %{items: items2} = result2
      assert length(items2) == 3
      assert %{items: items3} = result3
      assert length(items3) == 3
    end

    test "raises on invalid sample_size (zero)" do
      results = [{"tool", {:ok, [1, 2, 3]}}]

      assert_raise ArgumentError, ~r/sample_size must be a positive integer/, fn ->
        Sample.process(results, sample_size: 0)
      end
    end

    test "raises on invalid sample_size (negative)" do
      results = [{"tool", {:ok, [1, 2, 3]}}]

      assert_raise ArgumentError, ~r/sample_size must be a positive integer/, fn ->
        Sample.process(results, sample_size: -5)
      end
    end

    test "raises on invalid sample_size (non-integer)" do
      results = [{"tool", {:ok, [1, 2, 3]}}]

      assert_raise ArgumentError, ~r/sample_size must be a positive integer/, fn ->
        Sample.process(results, sample_size: "invalid")
      end
    end

    test "raises on invalid strategy" do
      results = [{"tool", {:ok, [1, 2, 3]}}]

      assert_raise ArgumentError, ~r/strategy must be one of/, fn ->
        Sample.process(results, sample_size: 3, strategy: :invalid)
      end
    end
  end
end
