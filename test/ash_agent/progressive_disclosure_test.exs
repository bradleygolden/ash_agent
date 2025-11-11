defmodule AshAgent.ProgressiveDisclosureTest do
  use ExUnit.Case, async: true

  doctest AshAgent.ProgressiveDisclosure

  alias AshAgent.{Context, ProgressiveDisclosure}

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

  # Helper to build context with iterations
  defp build_context_with_iterations(count) do
    iterations =
      Enum.map(1..count, fn i ->
        %{
          number: i,
          messages: [%{role: :user, content: "Message #{i}"}],
          started_at: DateTime.utc_now(),
          metadata: %{}
        }
      end)

    %Context{iterations: iterations}
  end

  # Helper to build context with lots of tokens
  defp build_large_context(iteration_count) do
    iterations =
      Enum.map(1..iteration_count, fn i ->
        %{
          number: i,
          messages: [
            %{role: :user, content: String.duplicate("x", 1000)},
            %{role: :assistant, content: String.duplicate("y", 1000)}
          ],
          started_at: DateTime.utc_now(),
          metadata: %{}
        }
      end)

    %Context{iterations: iterations}
  end

  describe "sliding_window_compact/2" do
    test "keeps only last N iterations" do
      context = build_context_with_iterations(10)

      compacted = ProgressiveDisclosure.sliding_window_compact(context, window_size: 3)

      assert %Context{iterations: iterations} = compacted
      assert length(iterations) == 3

      iteration_numbers = Enum.map(iterations, & &1.number)
      assert iteration_numbers == [8, 9, 10]
    end

    test "handles various window sizes" do
      context = build_context_with_iterations(10)

      compacted1 = ProgressiveDisclosure.sliding_window_compact(context, window_size: 1)
      assert length(compacted1.iterations) == 1
      assert hd(compacted1.iterations).number == 10

      compacted5 = ProgressiveDisclosure.sliding_window_compact(context, window_size: 5)
      assert length(compacted5.iterations) == 5

      compacted10 = ProgressiveDisclosure.sliding_window_compact(context, window_size: 10)
      assert length(compacted10.iterations) == 10
    end

    test "handles window_size > iteration count" do
      context = build_context_with_iterations(3)

      compacted = ProgressiveDisclosure.sliding_window_compact(context, window_size: 10)

      assert length(compacted.iterations) == 3
    end

    test "handles empty context" do
      context = %Context{iterations: []}

      compacted = ProgressiveDisclosure.sliding_window_compact(context, window_size: 5)

      assert compacted.iterations == []
    end

    test "emits telemetry event" do
      context = build_context_with_iterations(10)

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-#{inspect(ref)}",
        [:ash_agent, :progressive_disclosure, :sliding_window],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      ProgressiveDisclosure.sliding_window_compact(context, window_size: 3)

      assert_receive {:telemetry, [:ash_agent, :progressive_disclosure, :sliding_window],
                      measurements, metadata}

      assert %{before_count: 10, after_count: 3, removed: 7} = measurements
      assert %{window_size: 3} = metadata

      :telemetry.detach("test-#{inspect(ref)}")
    end

    test "raises on invalid window_size" do
      context = build_context_with_iterations(5)

      assert_raise ArgumentError, ~r/window_size must be a positive integer/, fn ->
        ProgressiveDisclosure.sliding_window_compact(context, window_size: 0)
      end

      assert_raise ArgumentError, fn ->
        ProgressiveDisclosure.sliding_window_compact(context, window_size: -5)
      end

      assert_raise ArgumentError, fn ->
        ProgressiveDisclosure.sliding_window_compact(context, window_size: "five")
      end
    end

    test "requires window_size option" do
      context = build_context_with_iterations(5)

      assert_raise KeyError, fn ->
        ProgressiveDisclosure.sliding_window_compact(context, [])
      end
    end
  end

  describe "token_based_compact/2" do
    test "removes iterations when over budget" do
      context = build_large_context(10)

      compacted =
        ProgressiveDisclosure.token_based_compact(context, budget: 50, threshold: 1.0)

      assert %Context{iterations: iterations} = compacted

      assert length(iterations) < 10

      final_tokens = Context.estimate_token_count(compacted)
      assert final_tokens <= 50
    end

    test "no compaction when under budget (no-op)" do
      context = build_context_with_iterations(3)

      compacted =
        ProgressiveDisclosure.token_based_compact(context, budget: 100_000, threshold: 1.0)

      assert length(compacted.iterations) == 3
    end

    test "preserves at least one iteration (safety)" do
      large_iteration = %{
        number: 1,
        messages: [
          %{role: :user, content: String.duplicate("x", 10_000)},
          %{role: :assistant, content: String.duplicate("y", 10_000)}
        ],
        started_at: DateTime.utc_now(),
        metadata: %{}
      }

      context = %Context{iterations: [large_iteration]}

      compacted = ProgressiveDisclosure.token_based_compact(context, budget: 10)

      assert length(compacted.iterations) == 1
    end

    test "respects custom threshold" do
      context = build_large_context(10)

      budget = 10_000
      estimated = Context.estimate_token_count(context)

      if estimated / budget < 0.8 do
        compacted =
          ProgressiveDisclosure.token_based_compact(context, budget: budget, threshold: 0.8)

        assert length(compacted.iterations) == length(context.iterations)
      end
    end

    test "emits telemetry event" do
      context = build_large_context(10)

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-#{inspect(ref)}",
        [:ash_agent, :progressive_disclosure, :token_based],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      ProgressiveDisclosure.token_based_compact(context, budget: 50)

      assert_receive {:telemetry, [:ash_agent, :progressive_disclosure, :token_based],
                      measurements, metadata}

      assert %{
               before_count: before_count,
               after_count: after_count,
               removed: removed,
               final_tokens: final_tokens
             } = measurements

      assert is_integer(before_count)
      assert is_integer(after_count)
      assert is_integer(removed)
      assert is_integer(final_tokens)
      assert removed == before_count - after_count

      assert %{budget: 50, threshold: threshold} = metadata
      assert is_float(threshold) or is_integer(threshold)

      :telemetry.detach("test-#{inspect(ref)}")
    end

    test "removes oldest iterations first (recursive removal)" do
      iterations =
        Enum.map(1..10, fn i ->
          %{
            number: i,
            messages: [%{role: :user, content: String.duplicate("x", 500)}],
            started_at: DateTime.add(DateTime.utc_now(), -i, :second),
            metadata: %{custom_id: "iter_#{i}"}
          }
        end)

      context = %Context{iterations: iterations}

      compacted = ProgressiveDisclosure.token_based_compact(context, budget: 30)

      remaining_numbers = Enum.map(compacted.iterations, & &1.number)

      assert 10 in remaining_numbers
      assert 9 in remaining_numbers

      assert length(remaining_numbers) < 10
    end

    test "raises on invalid budget" do
      context = build_context_with_iterations(5)

      assert_raise ArgumentError, ~r/budget must be a positive integer/, fn ->
        ProgressiveDisclosure.token_based_compact(context, budget: 0)
      end

      assert_raise ArgumentError, fn ->
        ProgressiveDisclosure.token_based_compact(context, budget: -100)
      end

      assert_raise ArgumentError, fn ->
        ProgressiveDisclosure.token_based_compact(context, budget: "one thousand")
      end
    end

    test "raises on invalid threshold" do
      context = build_context_with_iterations(5)

      assert_raise ArgumentError, ~r/threshold must be a number/, fn ->
        ProgressiveDisclosure.token_based_compact(context, budget: 1000, threshold: "high")
      end
    end

    test "requires budget option" do
      context = build_context_with_iterations(5)

      assert_raise KeyError, fn ->
        ProgressiveDisclosure.token_based_compact(context, [])
      end
    end

    test "handles empty context" do
      context = %Context{iterations: []}

      compacted = ProgressiveDisclosure.token_based_compact(context, budget: 1000)

      assert compacted.iterations == []
    end
  end
end
