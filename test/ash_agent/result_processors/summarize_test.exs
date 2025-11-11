defmodule AshAgent.ResultProcessors.SummarizeTest do
  use ExUnit.Case, async: true
  doctest AshAgent.ResultProcessors.Summarize

  alias AshAgent.ResultProcessors.Summarize

  describe "process/2 with list data" do
    test "summarizes large list with count and sample" do
      large_list = Enum.to_list(1..100)
      results = [{"query", {:ok, large_list}}]

      [{"query", {:ok, summary}}] = Summarize.process(results, sample_size: 3)

      assert summary.type == "list"
      assert summary.count == 100
      assert length(summary.sample) == 3
      assert summary.sample == [1, 2, 3]
      assert summary.summary == "List with 100 items"
    end

    test "summarizes small list completely" do
      small_list = [1, 2, 3]
      results = [{"query", {:ok, small_list}}]

      [{"query", {:ok, summary}}] = Summarize.process(results, sample_size: 5)

      assert summary.type == "list"
      assert summary.count == 3
      assert length(summary.sample) == 3
      assert summary.sample == [1, 2, 3]
    end

    test "handles empty list" do
      results = [{"query", {:ok, []}}]

      [{"query", {:ok, summary}}] = Summarize.process(results)

      assert summary.type == "list"
      assert summary.count == 0
      assert summary.sample == []
    end

    test "handles mixed-type list" do
      mixed_list = [1, "two", :three, %{four: 4}]
      results = [{"query", {:ok, mixed_list}}]

      [{"query", {:ok, summary}}] = Summarize.process(results, sample_size: 2)

      assert summary.type == "list"
      assert summary.count == 4
      # Each item gets summarized
      assert is_list(summary.sample)
      assert length(summary.sample) == 2
    end
  end

  describe "process/2 with map data" do
    test "summarizes large map with keys and sample values" do
      large_map = Map.new(1..50, fn i -> {:"key#{i}", "value#{i}"} end)
      results = [{"query", {:ok, large_map}}]

      [{"query", {:ok, summary}}] = Summarize.process(results, sample_size: 3)

      assert summary.type == "map"
      assert summary.count == 50
      assert is_list(summary.keys)
      assert length(summary.keys) == 3
      assert is_map(summary.sample)
      assert map_size(summary.sample) == 3
      assert summary.summary == "Map with 50 keys"
    end

    test "summarizes small map completely" do
      small_map = %{a: 1, b: 2, c: 3}
      results = [{"query", {:ok, small_map}}]

      [{"query", {:ok, summary}}] = Summarize.process(results, sample_size: 5)

      assert summary.type == "map"
      assert summary.count == 3
      assert length(summary.keys) == 3
      assert map_size(summary.sample) == 3
    end

    test "handles empty map" do
      results = [{"query", {:ok, %{}}}]

      [{"query", {:ok, summary}}] = Summarize.process(results)

      assert summary.type == "map"
      assert summary.count == 0
      assert summary.keys == []
      assert summary.sample == %{}
    end
  end

  describe "process/2 with text data" do
    test "summarizes long text with length and excerpt" do
      long_text = String.duplicate("Hello, world! ", 100)
      results = [{"query", {:ok, long_text}}]

      [{"query", {:ok, summary}}] = Summarize.process(results)

      assert summary.type == "text"
      assert summary.length == String.length(long_text)
      assert is_binary(summary.excerpt)
      assert byte_size(summary.excerpt) <= 200
      assert String.contains?(summary.summary, "characters")
    end

    test "handles short text" do
      short_text = "Hello!"
      results = [{"query", {:ok, short_text}}]

      [{"query", {:ok, summary}}] = Summarize.process(results)

      assert summary.type == "text"
      assert summary.length == 6
      assert summary.excerpt == "Hello!"
    end

    test "handles empty text" do
      results = [{"query", {:ok, ""}}]

      [{"query", {:ok, summary}}] = Summarize.process(results)

      assert summary.type == "text"
      assert summary.length == 0
      assert summary.excerpt == ""
    end
  end

  describe "process/2 with auto-detection" do
    test "auto-detects list type" do
      results = [{"tool", {:ok, [1, 2, 3, 4, 5]}}]

      [{"tool", {:ok, summary}}] = Summarize.process(results, strategy: :auto)

      assert summary.type == "list"
    end

    test "auto-detects map type" do
      results = [{"tool", {:ok, %{a: 1, b: 2}}}]

      [{"tool", {:ok, summary}}] = Summarize.process(results, strategy: :auto)

      assert summary.type == "map"
    end

    test "auto-detects text type" do
      results = [{"tool", {:ok, "some text"}}]

      [{"tool", {:ok, summary}}] = Summarize.process(results, strategy: :auto)

      assert summary.type == "text"
    end

    test "handles structs by converting to maps" do
      struct_data = %DateTime{
        year: 2025,
        month: 11,
        day: 10,
        hour: 12,
        minute: 0,
        second: 0,
        microsecond: {0, 0},
        time_zone: "Etc/UTC",
        zone_abbr: "UTC",
        utc_offset: 0,
        std_offset: 0,
        calendar: Calendar.ISO
      }

      results = [{"tool", {:ok, struct_data}}]

      [{"tool", {:ok, summary}}] = Summarize.process(results)

      assert summary.type == "struct"
      assert summary.struct_name == "DateTime"
      assert is_map(summary.fields)
      assert String.contains?(summary.summary, "DateTime")
    end
  end

  describe "process/2 with nested structures" do
    test "handles nested list with depth limit" do
      nested = [[[[[[["too deep"]]]]]], "shallow"]
      results = [{"tool", {:ok, nested}}]

      [{"tool", {:ok, summary}}] = Summarize.process(results, sample_size: 2)

      assert summary.type == "list"
      # Should summarize without infinite recursion
      assert is_list(summary.sample)
    end

    test "handles nested maps with depth limit" do
      nested = %{
        level1: %{
          level2: %{
            level3: %{
              level4: %{
                level5: "too deep"
              }
            }
          }
        }
      }

      results = [{"tool", {:ok, nested}}]

      [{"tool", {:ok, summary}}] = Summarize.process(results)

      assert summary.type == "map"
      # Should summarize without infinite recursion
      assert is_map(summary.sample)
    end
  end

  describe "process/2 with error results" do
    test "preserves error results unchanged" do
      results = [
        {"success", {:ok, [1, 2, 3]}},
        {"failure", {:error, "something went wrong"}},
        {"another", {:ok, "data"}}
      ]

      processed = Summarize.process(results)

      # Success results are summarized
      [{"success", {:ok, summary1}}, {"failure", error}, {"another", {:ok, summary2}}] =
        processed

      assert is_map(summary1)
      assert summary1.type == "list"
      assert error == {:error, "something went wrong"}
      assert is_map(summary2)
      assert summary2.type == "text"
    end
  end

  describe "process/2 with edge cases" do
    test "sample size option controls sample count" do
      results = [{"tool", {:ok, Enum.to_list(1..100)}}]

      [{"tool", {:ok, summary1}}] = Summarize.process(results, sample_size: 2)
      [{"tool", {:ok, summary2}}] = Summarize.process(results, sample_size: 5)

      assert length(summary1.sample) == 2
      assert length(summary2.sample) == 5
    end

    test "max_summary_size enforces size limit" do
      # Create a large list that will produce a big summary
      large_list = Enum.to_list(1..1000)
      results = [{"tool", {:ok, large_list}}]

      [{"tool", {:ok, summary}}] = Summarize.process(results, max_summary_size: 100)

      # Summary should be limited in size
      summary_size = :erlang.external_size(summary)
      assert summary_size < 1000
    end

    test "handles multiple results in batch" do
      results = [
        {"tool1", {:ok, [1, 2, 3]}},
        {"tool2", {:ok, %{a: 1, b: 2}}},
        {"tool3", {:ok, "some text"}}
      ]

      processed = Summarize.process(results)

      assert length(processed) == 3

      [{"tool1", {:ok, sum1}}, {"tool2", {:ok, sum2}}, {"tool3", {:ok, sum3}}] = processed

      assert sum1.type == "list"
      assert sum2.type == "map"
      assert sum3.type == "text"
    end

    test "raises on invalid sample_size" do
      results = [{"tool", {:ok, [1, 2, 3]}}]

      assert_raise ArgumentError, fn ->
        Summarize.process(results, sample_size: -1)
      end

      assert_raise ArgumentError, fn ->
        Summarize.process(results, sample_size: 0)
      end
    end

    test "raises on invalid max_summary_size" do
      results = [{"tool", {:ok, [1, 2, 3]}}]

      assert_raise ArgumentError, fn ->
        Summarize.process(results, max_summary_size: -1)
      end

      assert_raise ArgumentError, fn ->
        Summarize.process(results, max_summary_size: 0)
      end
    end
  end
end
