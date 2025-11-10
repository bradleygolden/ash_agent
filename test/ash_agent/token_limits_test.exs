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
end
