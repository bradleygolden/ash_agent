defmodule AshAgent.ResultProcessors.TruncateTest do
  use ExUnit.Case, async: true

  alias AshAgent.ResultProcessors.Truncate

  describe "process/2 with binary data" do
    test "truncates binary over max_size (UTF-8 safe)" do
      large_binary = String.duplicate("x", 2000)
      results = [{"tool", {:ok, large_binary}}]

      assert [{"tool", {:ok, truncated}}] = Truncate.process(results, max_size: 100)
      assert is_binary(truncated)
      # Should be ~100 chars + marker (not 2000!)
      assert String.length(truncated) <= 120
      assert String.contains?(truncated, "... [truncated]")
    end

    test "preserves binary under max_size" do
      small_binary = "small data"
      results = [{"tool", {:ok, small_binary}}]

      assert [{"tool", {:ok, ^small_binary}}] = Truncate.process(results, max_size: 100)
    end

    test "handles empty binary" do
      empty_binary = ""
      results = [{"tool", {:ok, empty_binary}}]

      assert [{"tool", {:ok, ^empty_binary}}] = Truncate.process(results, max_size: 100)
    end

    test "handles unicode multi-byte character boundaries" do
      # String with emoji and multi-byte characters
      unicode_string = String.duplicate("🎉", 100)
      results = [{"tool", {:ok, unicode_string}}]

      assert [{"tool", {:ok, truncated}}] = Truncate.process(results, max_size: 10)
      assert is_binary(truncated)
      # Should not crash with invalid UTF-8!
      assert String.valid?(truncated)
      # Should be truncated
      assert String.length(truncated) < String.length(unicode_string)
    end
  end

  describe "process/2 with list data" do
    test "truncates list over max_size" do
      large_list = Enum.to_list(1..2000)
      results = [{"tool", {:ok, large_list}}]

      assert [{"tool", {:ok, truncated}}] = Truncate.process(results, max_size: 10)
      assert is_list(truncated)
      # Should be ~10 items + marker
      assert length(truncated) <= 11
      assert List.last(truncated) == "... [truncated]"
    end

    test "preserves list under max_size" do
      small_list = [1, 2, 3]
      results = [{"tool", {:ok, small_list}}]

      assert [{"tool", {:ok, ^small_list}}] = Truncate.process(results, max_size: 100)
    end

    test "handles empty list" do
      empty_list = []
      results = [{"tool", {:ok, empty_list}}]

      assert [{"tool", {:ok, ^empty_list}}] = Truncate.process(results, max_size: 100)
    end
  end

  describe "process/2 with map data" do
    test "truncates map over max_size" do
      large_map = Map.new(1..2000, fn i -> {i, "value_#{i}"} end)
      results = [{"tool", {:ok, large_map}}]

      assert [{"tool", {:ok, truncated}}] = Truncate.process(results, max_size: 10)
      assert is_map(truncated)
      # Should be ~10 keys + marker
      assert map_size(truncated) <= 11
      assert Map.has_key?(truncated, :__truncated__)
    end

    test "preserves map under max_size" do
      small_map = %{a: 1, b: 2, c: 3}
      results = [{"tool", {:ok, small_map}}]

      assert [{"tool", {:ok, ^small_map}}] = Truncate.process(results, max_size: 100)
    end

    test "handles empty map" do
      empty_map = %{}
      results = [{"tool", {:ok, empty_map}}]

      assert [{"tool", {:ok, ^empty_map}}] = Truncate.process(results, max_size: 100)
    end
  end

  describe "process/2 with error results" do
    test "preserves error results unchanged" do
      error_result = {:error, "something went wrong"}
      results = [{"tool", error_result}]

      assert [{"tool", ^error_result}] = Truncate.process(results, max_size: 100)
    end
  end

  describe "process/2 with edge cases" do
    test "handles truncation marker verification" do
      large_binary = String.duplicate("x", 2000)
      results = [{"tool", {:ok, large_binary}}]

      assert [{"tool", {:ok, truncated}}] = Truncate.process(results, max_size: 100)
      # Should contain default marker
      assert String.contains?(truncated, "... [truncated]")
    end

    test "supports custom marker option" do
      large_binary = String.duplicate("x", 2000)
      results = [{"tool", {:ok, large_binary}}]

      assert [{"tool", {:ok, truncated}}] =
               Truncate.process(results, max_size: 100, marker: "...MORE")

      # Should contain custom marker
      assert String.contains?(truncated, "...MORE")
      refute String.contains?(truncated, "... [truncated]")
    end

    test "handles invalid max_size (negative)" do
      results = [{"tool", {:ok, "data"}}]

      assert_raise ArgumentError, ~r/max_size must be a positive integer/, fn ->
        Truncate.process(results, max_size: -1)
      end
    end

    test "handles invalid max_size (zero)" do
      results = [{"tool", {:ok, "data"}}]

      assert_raise ArgumentError, ~r/max_size must be a positive integer/, fn ->
        Truncate.process(results, max_size: 0)
      end
    end

    test "handles multiple results in single batch" do
      results = [
        {"tool1", {:ok, String.duplicate("a", 2000)}},
        {"tool2", {:ok, Enum.to_list(1..2000)}},
        {"tool3", {:ok, %{data: "small"}}}
      ]

      assert [
               {"tool1", {:ok, truncated1}},
               {"tool2", {:ok, truncated2}},
               {"tool3", {:ok, small_map}}
             ] = Truncate.process(results, max_size: 10)

      # Tool1 should be truncated
      assert String.length(truncated1) <= 30
      assert String.contains?(truncated1, "... [truncated]")

      # Tool2 should be truncated
      assert length(truncated2) <= 11

      # Tool3 should be unchanged (under threshold)
      assert small_map == %{data: "small"}
    end

    test "handles nested structure truncation" do
      nested_data = %{
        list: Enum.to_list(1..100),
        map: Map.new(1..100, fn i -> {i, "value_#{i}"} end),
        binary: String.duplicate("x", 1000)
      }

      results = [{"tool", {:ok, nested_data}}]

      # Truncate at top level (map keys)
      assert [{"tool", {:ok, truncated}}] = Truncate.process(results, max_size: 2)
      assert is_map(truncated)
      # Should have at most 3 keys (2 + truncation marker)
      assert map_size(truncated) <= 3
      assert Map.has_key?(truncated, :__truncated__)
    end
  end
end
