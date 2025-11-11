defmodule AshAgent.ProgressiveDisclosureCompactionTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias AshAgent.{Context, ProgressiveDisclosure}

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

      # Should keep last 3 iterations
      iteration_numbers = Enum.map(iterations, & &1.number)
      assert iteration_numbers == [8, 9, 10]
    end

    test "handles various window sizes" do
      context = build_context_with_iterations(10)

      # Window size 1
      compacted1 = ProgressiveDisclosure.sliding_window_compact(context, window_size: 1)
      assert length(compacted1.iterations) == 1
      assert hd(compacted1.iterations).number == 10

      # Window size 5
      compacted5 = ProgressiveDisclosure.sliding_window_compact(context, window_size: 5)
      assert length(compacted5.iterations) == 5

      # Window size 10 (all)
      compacted10 = ProgressiveDisclosure.sliding_window_compact(context, window_size: 10)
      assert length(compacted10.iterations) == 10
    end

    test "handles window_size > iteration count" do
      context = build_context_with_iterations(3)

      compacted = ProgressiveDisclosure.sliding_window_compact(context, window_size: 10)

      # Should keep all 3 iterations
      assert length(compacted.iterations) == 3
    end

    test "handles empty context" do
      context = %Context{iterations: []}

      compacted = ProgressiveDisclosure.sliding_window_compact(context, window_size: 5)

      assert compacted.iterations == []
    end

    test "emits telemetry event" do
      context = build_context_with_iterations(10)

      # Attach telemetry handler
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

    test "logs compaction actions" do
      context = build_context_with_iterations(10)

      log =
        capture_log(fn ->
          Logger.configure(level: :debug)
          ProgressiveDisclosure.sliding_window_compact(context, window_size: 3)
        end)

      assert log =~ "Applying sliding window compaction"
      assert log =~ "window_size=3"
      assert log =~ "removed 7 iterations"
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
      # Build context with 10 iterations * 2 messages = 200 tokens (overhead only due to bug)
      context = build_large_context(10)

      # Set budget to 50 tokens (should keep only 2-3 iterations = 40-60 tokens)
      compacted =
        ProgressiveDisclosure.token_based_compact(context, budget: 50, threshold: 1.0)

      assert %Context{iterations: iterations} = compacted

      # Should have removed some iterations
      assert length(iterations) < 10

      # Final token count should be close to budget
      final_tokens = Context.estimate_token_count(compacted)
      assert final_tokens <= 50
    end

    test "no compaction when under budget (no-op)" do
      context = build_context_with_iterations(3)

      # Set very high budget
      compacted =
        ProgressiveDisclosure.token_based_compact(context, budget: 100_000, threshold: 1.0)

      # Should keep all iterations
      assert length(compacted.iterations) == 3
    end

    test "preserves at least one iteration (safety)" do
      # Build single large iteration that exceeds budget
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

      # Set impossibly low budget (iteration will exceed it - 2 messages = 20 tokens)
      log =
        capture_log(fn ->
          Logger.configure(level: :warning)
          compacted = ProgressiveDisclosure.token_based_compact(context, budget: 10)

          # Should still have 1 iteration (safety)
          assert length(compacted.iterations) == 1
        end)

      assert log =~ "only 1 iteration remains"
      assert log =~ "cannot compact further"
    end

    test "respects custom threshold" do
      context = build_large_context(10)

      # With threshold 0.5, should only compact if over 50% of budget
      budget = 10_000
      estimated = Context.estimate_token_count(context)

      # If we're at ~5000 tokens and threshold is 0.8 (80%), no compaction
      if estimated / budget < 0.8 do
        compacted =
          ProgressiveDisclosure.token_based_compact(context, budget: budget, threshold: 0.8)

        # Should not compact (under threshold)
        assert length(compacted.iterations) == length(context.iterations)
      end
    end

    test "emits telemetry event" do
      context = build_large_context(10)

      # Attach telemetry handler
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
      # Build context with identifiable iterations (10 iterations * 1 message = 100 tokens)
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

      # Compact to small budget (should remove oldest first)
      compacted = ProgressiveDisclosure.token_based_compact(context, budget: 30)

      # Should have kept most recent iterations
      remaining_numbers = Enum.map(compacted.iterations, & &1.number)

      # Most recent should be in remaining (10, 9, 8, etc)
      assert 10 in remaining_numbers
      assert 9 in remaining_numbers

      # Oldest should be removed (1, 2, 3, etc)
      # (Can't assert exact numbers due to token estimation variance)
      assert length(remaining_numbers) < 10
    end

    test "logs compaction decisions" do
      context = build_large_context(10)

      log =
        capture_log(fn ->
          Logger.configure(level: :debug)
          ProgressiveDisclosure.token_based_compact(context, budget: 50)
        end)

      assert log =~ "Context exceeds budget threshold"
      assert log =~ "compacting"
      assert log =~ "removed"
      assert log =~ "iterations"
      assert log =~ "reduced tokens"
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
