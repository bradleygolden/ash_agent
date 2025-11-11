defmodule AshAgent.ContextIterationManagementTest do
  use ExUnit.Case, async: true

  alias AshAgent.Context

  describe "keep_last_iterations/2" do
    test "keeps only the last N iterations" do
      iterations = [
        %{number: 1, started_at: ~U[2025-01-01 10:00:00Z]},
        %{number: 2, started_at: ~U[2025-01-01 11:00:00Z]},
        %{number: 3, started_at: ~U[2025-01-01 12:00:00Z]},
        %{number: 4, started_at: ~U[2025-01-01 13:00:00Z]},
        %{number: 5, started_at: ~U[2025-01-01 14:00:00Z]}
      ]

      context = %Context{iterations: iterations}

      result = Context.keep_last_iterations(context, 2)

      assert %Context{iterations: kept} = result
      assert length(kept) == 2
      assert [%{number: 4}, %{number: 5}] = kept
    end

    test "keeps all iterations when count > iteration count" do
      iterations = [
        %{number: 1},
        %{number: 2}
      ]

      context = %Context{iterations: iterations}

      result = Context.keep_last_iterations(context, 10)

      assert %Context{iterations: kept} = result
      assert length(kept) == 2
      assert kept == iterations
    end

    test "keeps only one iteration when count = 1" do
      iterations = [
        %{number: 1},
        %{number: 2},
        %{number: 3}
      ]

      context = %Context{iterations: iterations}

      result = Context.keep_last_iterations(context, 1)

      assert %Context{iterations: [%{number: 3}]} = result
    end

    test "handles empty context" do
      context = %Context{iterations: []}

      result = Context.keep_last_iterations(context, 5)

      assert %Context{iterations: []} = result
    end

    test "does not modify original context (immutability)" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      _result = Context.keep_last_iterations(context, 1)

      # Original unchanged
      assert context.iterations == iterations
      assert length(context.iterations) == 3
    end
  end

  describe "remove_old_iterations/2" do
    test "removes iterations older than specified age" do
      now = DateTime.utc_now()
      two_hours_ago = DateTime.add(now, -2 * 3600, :second)
      one_hour_ago = DateTime.add(now, -1 * 3600, :second)

      iterations = [
        %{number: 1, started_at: two_hours_ago},
        %{number: 2, started_at: one_hour_ago},
        %{number: 3, started_at: now}
      ]

      context = %Context{iterations: iterations}

      # Remove iterations older than 90 minutes (5400 seconds)
      result = Context.remove_old_iterations(context, 5400)

      assert %Context{iterations: kept} = result
      assert length(kept) == 2
      # Should keep iterations 2 and 3 (within 90 minutes)
      assert Enum.map(kept, & &1.number) == [2, 3]
    end

    test "keeps all iterations when none are old" do
      now = DateTime.utc_now()
      recent = DateTime.add(now, -60, :second)

      iterations = [
        %{number: 1, started_at: recent},
        %{number: 2, started_at: now}
      ]

      context = %Context{iterations: iterations}

      # Remove iterations older than 1 hour
      result = Context.remove_old_iterations(context, 3600)

      assert %Context{iterations: kept} = result
      assert length(kept) == 2
      assert kept == iterations
    end

    test "removes all old iterations" do
      old = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)

      iterations = [
        %{number: 1, started_at: old},
        %{number: 2, started_at: old}
      ]

      context = %Context{iterations: iterations}

      # Remove iterations older than 1 hour
      result = Context.remove_old_iterations(context, 3600)

      assert %Context{iterations: []} = result
    end

    test "keeps iterations with missing timestamps" do
      old = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)

      iterations = [
        %{number: 1, started_at: old},
        %{number: 2},
        # No started_at field
        %{number: 3, started_at: DateTime.utc_now()}
      ]

      context = %Context{iterations: iterations}

      # Remove iterations older than 1 hour
      result = Context.remove_old_iterations(context, 3600)

      assert %Context{iterations: kept} = result
      # Should keep iteration 2 (no timestamp) and 3 (recent)
      assert length(kept) == 2
      assert Enum.map(kept, & &1.number) == [2, 3]
    end

    test "does not modify original context (immutability)" do
      old = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)
      iterations = [%{number: 1, started_at: old}]
      context = %Context{iterations: iterations}

      _result = Context.remove_old_iterations(context, 3600)

      # Original unchanged
      assert context.iterations == iterations
    end
  end

  describe "count_iterations/1" do
    test "returns count of iterations" do
      context = %Context{
        iterations: [
          %{number: 1},
          %{number: 2},
          %{number: 3}
        ]
      }

      assert Context.count_iterations(context) == 3
    end

    test "returns 0 for empty context" do
      context = %Context{iterations: []}

      assert Context.count_iterations(context) == 0
    end

    test "returns correct count for single iteration" do
      context = %Context{iterations: [%{number: 1}]}

      assert Context.count_iterations(context) == 1
    end
  end

  describe "get_iteration_range/3" do
    test "returns slice of iterations" do
      iterations = [
        %{number: 1},
        %{number: 2},
        %{number: 3},
        %{number: 4},
        %{number: 5}
      ]

      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 1, 3)

      assert %Context{iterations: sliced} = result
      assert length(sliced) == 3
      assert [%{number: 2}, %{number: 3}, %{number: 4}] = sliced
    end

    test "handles out of bounds start index" do
      iterations = [%{number: 1}, %{number: 2}]
      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 10, 15)

      assert %Context{iterations: []} = result
    end

    test "handles out of bounds end index" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 1, 10)

      assert %Context{iterations: sliced} = result
      # Should get from index 1 to end
      assert [%{number: 2}, %{number: 3}] = sliced
    end

    test "returns single iteration when start == end" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 1, 1)

      assert %Context{iterations: [%{number: 2}]} = result
    end

    test "returns all iterations when range covers all" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 0, 2)

      assert %Context{iterations: sliced} = result
      assert sliced == iterations
    end

    test "preserves iteration ordering" do
      iterations = [
        %{number: 1},
        %{number: 2},
        %{number: 3},
        %{number: 4}
      ]

      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 0, 2)

      assert %Context{iterations: [%{number: 1}, %{number: 2}, %{number: 3}]} = result
    end

    test "does not modify original context (immutability)" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      _result = Context.get_iteration_range(context, 0, 1)

      # Original unchanged
      assert context.iterations == iterations
    end
  end
end
