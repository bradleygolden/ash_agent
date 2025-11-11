defmodule AshAgent.ProgressiveDisclosureTest do
  use ExUnit.Case, async: true

  alias AshAgent.ProgressiveDisclosure

  describe "process_tool_results/2 with single processor" do
    test "applies truncate only" do
      large_data = String.duplicate("x", 2000)
      results = [{"tool1", {:ok, large_data}}]

      processed = ProgressiveDisclosure.process_tool_results(results, truncate: 100)

      assert [{"tool1", {:ok, truncated}}] = processed
      assert is_binary(truncated)
      assert byte_size(truncated) <= 120
      assert String.contains?(truncated, "[truncated]")
    end

    test "applies summarize only" do
      large_list = Enum.to_list(1..100)
      results = [{"tool1", {:ok, large_list}}]

      # Force processing with skip_small: false
      processed =
        ProgressiveDisclosure.process_tool_results(results, summarize: true, skip_small: false)

      assert [{"tool1", {:ok, summary}}] = processed
      assert is_map(summary)
      assert summary.type == "list"
      assert summary.count == 100
    end

    test "applies sample only" do
      large_list = Enum.to_list(1..100)
      results = [{"tool1", {:ok, large_list}}]

      # Force processing with skip_small: false
      processed =
        ProgressiveDisclosure.process_tool_results(results, sample: 5, skip_small: false)

      assert [{"tool1", {:ok, sampled}}] = processed
      assert is_map(sampled)
      assert sampled.items == [1, 2, 3, 4, 5]
      assert sampled.total_count == 100
    end
  end

  describe "process_tool_results/2 with multiple processors" do
    test "applies all options (truncate + summarize + sample)" do
      large_data = String.duplicate("x", 2000)
      results = [{"tool1", {:ok, large_data}}]

      processed =
        ProgressiveDisclosure.process_tool_results(results,
          truncate: 100,
          summarize: true,
          sample: 5
        )

      # Should be processed through pipeline
      assert [{"tool1", {:ok, _result}}] = processed
    end

    test "processor composition order matters (truncate → summarize → sample)" do
      # Start with a large list
      large_list = Enum.to_list(1..100)
      results = [{"tool1", {:ok, large_list}}]

      # Apply sample first (should sample the list)
      sampled =
        ProgressiveDisclosure.process_tool_results(results,
          sample: 5,
          skip_small: false
        )

      assert [{"tool1", {:ok, result}}] = sampled
      assert result.items == [1, 2, 3, 4, 5]

      # Apply summarize (should summarize the list)
      summarized =
        ProgressiveDisclosure.process_tool_results(results,
          summarize: true,
          skip_small: false
        )

      assert [{"tool1", {:ok, result}}] = summarized
      assert result.type == "list"
    end

    test "custom summarize options as keyword list" do
      large_list = Enum.to_list(1..100)
      results = [{"tool1", {:ok, large_list}}]

      processed =
        ProgressiveDisclosure.process_tool_results(results,
          summarize: [sample_size: 10],
          skip_small: false
        )

      assert [{"tool1", {:ok, summary}}] = processed
      assert is_map(summary)
      assert summary.type == "list"
      assert length(summary.sample) == 10
    end
  end

  describe "process_tool_results/2 with no options" do
    test "passes through results unchanged" do
      results = [{"tool1", {:ok, "data"}}]

      processed = ProgressiveDisclosure.process_tool_results(results, [])

      assert processed == results
    end

    test "skip optimization when all results are small" do
      small_data = "small"

      results = [
        {"tool1", {:ok, small_data}},
        {"tool2", {:ok, small_data}}
      ]

      # With truncate: 1000, these should be skipped
      processed = ProgressiveDisclosure.process_tool_results(results, truncate: 1000)

      assert processed == results
    end

    test "no skip when at least one result is large" do
      small_data = "small"
      large_data = String.duplicate("x", 2000)

      results = [
        {"tool1", {:ok, small_data}},
        {"tool2", {:ok, large_data}}
      ]

      # Should process because tool2 is large
      processed = ProgressiveDisclosure.process_tool_results(results, truncate: 100)

      # Small result unchanged
      assert [{"tool1", {:ok, ^small_data}}, {"tool2", {:ok, truncated}}] = processed
      assert is_binary(truncated)
      assert byte_size(truncated) <= 120
    end
  end

  describe "process_tool_results/2 with edge cases" do
    test "handles empty results list" do
      results = []

      processed = ProgressiveDisclosure.process_tool_results(results, truncate: 100)

      assert processed == []
    end

    test "handles all error results" do
      results = [
        {"tool1", {:error, "failure"}},
        {"tool2", {:error, "another failure"}}
      ]

      processed =
        ProgressiveDisclosure.process_tool_results(results,
          truncate: 100,
          summarize: true
        )

      # Errors should pass through unchanged
      assert processed == results
    end

    test "handles mixed result sizes in batch" do
      results = [
        {"small", {:ok, "tiny"}},
        {"medium", {:ok, String.duplicate("x", 500)}},
        {"large", {:ok, String.duplicate("y", 2000)}},
        {"error", {:error, "fail"}}
      ]

      processed = ProgressiveDisclosure.process_tool_results(results, truncate: 100)

      assert [
               {"small", {:ok, small_result}},
               {"medium", {:ok, medium_result}},
               {"large", {:ok, large_result}},
               {"error", {:error, "fail"}}
             ] = processed

      # Small unchanged
      assert small_result == "tiny"

      # Medium and large truncated
      assert byte_size(medium_result) <= 120
      assert byte_size(large_result) <= 120
    end
  end

  describe "process_tool_results/2 with skip_small option" do
    test "skip_small: false forces processing even for small results" do
      small_data = "small"
      results = [{"tool1", {:ok, small_data}}]

      # Force processing
      processed =
        ProgressiveDisclosure.process_tool_results(results,
          truncate: 100,
          skip_small: false
        )

      # Should still pass through unchanged (no truncation needed)
      assert processed == results
    end

    test "skip_small: true (default) skips when all small" do
      small_data = "small"
      results = [{"tool1", {:ok, small_data}}]

      processed = ProgressiveDisclosure.process_tool_results(results, truncate: 1000)

      assert processed == results
    end
  end

  describe "process_tool_results/2 telemetry" do
    test "emits telemetry event when processing" do
      large_data = String.duplicate("x", 2000)
      results = [{"tool1", {:ok, large_data}}]

      # Attach telemetry handler
      ref = make_ref()

      :telemetry.attach(
        "test-pd-#{inspect(ref)}",
        [:ash_agent, :progressive_disclosure, :process_results],
        fn name, measurements, metadata, _ ->
          send(self(), {:telemetry_event, name, measurements, metadata})
        end,
        nil
      )

      _processed = ProgressiveDisclosure.process_tool_results(results, truncate: 100)

      # Should receive telemetry event
      assert_receive {:telemetry_event, [:ash_agent, :progressive_disclosure, :process_results],
                      measurements, metadata}

      assert measurements.count == 1
      assert measurements.skipped == false
      assert metadata.options == [truncate: 100]

      :telemetry.detach("test-pd-#{inspect(ref)}")
    end

    test "emits telemetry event when skipping" do
      small_data = "small"
      results = [{"tool1", {:ok, small_data}}]

      # Attach telemetry handler
      ref = make_ref()

      :telemetry.attach(
        "test-pd-skip-#{inspect(ref)}",
        [:ash_agent, :progressive_disclosure, :process_results],
        fn name, measurements, metadata, _ ->
          send(self(), {:telemetry_event, name, measurements, metadata})
        end,
        nil
      )

      _processed = ProgressiveDisclosure.process_tool_results(results, truncate: 1000)

      # Should receive telemetry event
      assert_receive {:telemetry_event, [:ash_agent, :progressive_disclosure, :process_results],
                      measurements, metadata}

      assert measurements.count == 1
      assert measurements.skipped == true
      assert metadata.options == [truncate: 1000]

      :telemetry.detach("test-pd-skip-#{inspect(ref)}")
    end
  end
end
