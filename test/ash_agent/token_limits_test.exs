defmodule AshAgent.TokenLimitsTest do
  use ExUnit.Case, async: true

  alias AshAgent.TokenLimits

  describe "get_limit/2" do
    test "returns configured limit for known provider" do
      limits = %{
        "anthropic:claude-3-5-sonnet" => 200_000,
        "openai:gpt-4" => 128_000,
        "openai:gpt-3.5-turbo" => 16_385
      }

      assert TokenLimits.get_limit("anthropic:claude-3-5-sonnet", limits) == 200_000
      assert TokenLimits.get_limit("openai:gpt-4", limits) == 128_000
      assert TokenLimits.get_limit("openai:gpt-3.5-turbo", limits) == 16_385
    end

    test "returns nil for unknown provider" do
      assert TokenLimits.get_limit("unknown:model", %{}) == nil
    end

    test "returns custom limit from provided config" do
      limits = %{"custom:model" => 50_000}

      assert TokenLimits.get_limit("custom:model", limits) == 50_000
    end

    test "can override configured limit" do
      limits = %{"anthropic:claude-3-5-sonnet" => 100_000}

      assert TokenLimits.get_limit("anthropic:claude-3-5-sonnet", limits) == 100_000
    end
  end

  describe "get_warning_threshold/1" do
    test "returns default threshold of 0.8" do
      assert TokenLimits.get_warning_threshold() == 0.8
    end

    test "returns custom threshold when provided" do
      assert TokenLimits.get_warning_threshold(0.9) == 0.9
    end
  end

  describe "check_limit/4" do
    test "returns :ok when below threshold" do
      limits = %{"anthropic:claude-3-5-sonnet" => 200_000}

      assert TokenLimits.check_limit(100_000, "anthropic:claude-3-5-sonnet", limits) == :ok
    end

    test "returns {:warn, limit, threshold} when at threshold" do
      limits = %{"anthropic:claude-3-5-sonnet" => 200_000}

      assert {:warn, 200_000, 0.8} =
               TokenLimits.check_limit(160_000, "anthropic:claude-3-5-sonnet", limits)
    end

    test "returns :ok when just below threshold" do
      limits = %{"anthropic:claude-3-5-sonnet" => 200_000}

      assert TokenLimits.check_limit(159_999, "anthropic:claude-3-5-sonnet", limits) == :ok
    end

    test "returns :ok for unknown provider" do
      assert TokenLimits.check_limit(999_999, "unknown:model", %{}) == :ok
    end

    test "respects custom threshold" do
      limits = %{"anthropic:claude-3-5-sonnet" => 200_000}

      assert {:warn, 200_000, 0.5} =
               TokenLimits.check_limit(100_000, "anthropic:claude-3-5-sonnet", limits, 0.5)

      assert TokenLimits.check_limit(99_999, "anthropic:claude-3-5-sonnet", limits, 0.5) == :ok
    end
  end

  describe "check_limit/6 with budget and strategy" do
    test "returns :ok when below budget with halt strategy" do
      assert TokenLimits.check_limit(50_000, "anthropic:claude", nil, nil, 100_000, :halt) ==
               :ok
    end

    test "returns {:error, :budget_exceeded} when at budget with halt strategy" do
      assert TokenLimits.check_limit(100_000, "anthropic:claude", nil, nil, 100_000, :halt) ==
               {:error, :budget_exceeded}
    end

    test "returns {:error, :budget_exceeded} when over budget with halt strategy" do
      assert TokenLimits.check_limit(150_000, "anthropic:claude", nil, nil, 100_000, :halt) ==
               {:error, :budget_exceeded}
    end

    test "returns {:warn, budget, threshold} when at threshold with warn strategy" do
      assert {:warn, 100_000, 0.8} =
               TokenLimits.check_limit(80_000, "anthropic:claude", nil, nil, 100_000, :warn)
    end

    test "returns :ok when over budget with warn strategy but below threshold" do
      assert TokenLimits.check_limit(50_000, "anthropic:claude", nil, nil, 100_000, :warn) ==
               :ok
    end

    test "budget takes precedence over provider limits" do
      limits = %{"anthropic:claude-3-5-sonnet" => 200_000}

      assert {:error, :budget_exceeded} =
               TokenLimits.check_limit(
                 100_000,
                 "anthropic:claude-3-5-sonnet",
                 limits,
                 nil,
                 50_000,
                 :halt
               )
    end

    test "uses provider limit when no budget configured with warn strategy" do
      limits = %{"anthropic:claude-3-5-sonnet" => 200_000}

      assert {:warn, 200_000, 0.8} =
               TokenLimits.check_limit(
                 180_000,
                 "anthropic:claude-3-5-sonnet",
                 limits,
                 nil,
                 nil,
                 :warn
               )
    end

    test "returns :ok when no budget and no provider limit configured" do
      assert TokenLimits.check_limit(999_999, "unknown:model", nil, nil, nil, :halt) == :ok
    end

    test "defaults to warn strategy when not specified" do
      assert {:warn, 100_000, 0.8} =
               TokenLimits.check_limit(80_000, "anthropic:claude", nil, nil, 100_000)
    end
  end
end
