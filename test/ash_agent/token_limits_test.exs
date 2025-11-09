defmodule AshAgent.TokenLimitsTest do
  use ExUnit.Case, async: false

  alias AshAgent.TokenLimits

  describe "get_limit/1" do
    test "returns default limit for known provider" do
      assert TokenLimits.get_limit("anthropic:claude-3-5-sonnet") == 200_000
      assert TokenLimits.get_limit("openai:gpt-4") == 128_000
      assert TokenLimits.get_limit("openai:gpt-3.5-turbo") == 16_385
    end

    test "returns nil for unknown provider" do
      assert TokenLimits.get_limit("unknown:model") == nil
    end

    test "returns custom limit from application config" do
      original = Application.get_env(:ash_agent, :token_limits)

      try do
        Application.put_env(:ash_agent, :token_limits, %{
          "custom:model" => 50_000
        })

        assert TokenLimits.get_limit("custom:model") == 50_000
      after
        if original do
          Application.put_env(:ash_agent, :token_limits, original)
        else
          Application.delete_env(:ash_agent, :token_limits)
        end
      end
    end

    test "custom config overrides default limit" do
      original = Application.get_env(:ash_agent, :token_limits)

      try do
        Application.put_env(:ash_agent, :token_limits, %{
          "anthropic:claude-3-5-sonnet" => 100_000
        })

        assert TokenLimits.get_limit("anthropic:claude-3-5-sonnet") == 100_000
      after
        if original do
          Application.put_env(:ash_agent, :token_limits, original)
        else
          Application.delete_env(:ash_agent, :token_limits)
        end
      end
    end
  end

  describe "get_warning_threshold/0" do
    test "returns default threshold of 0.8" do
      assert TokenLimits.get_warning_threshold() == 0.8
    end

    test "returns custom threshold from application config" do
      original = Application.get_env(:ash_agent, :token_warning_threshold)

      try do
        Application.put_env(:ash_agent, :token_warning_threshold, 0.9)

        assert TokenLimits.get_warning_threshold() == 0.9
      after
        if original do
          Application.put_env(:ash_agent, :token_warning_threshold, original)
        else
          Application.delete_env(:ash_agent, :token_warning_threshold)
        end
      end
    end
  end

  describe "check_limit/2" do
    test "returns :ok when below threshold" do
      assert TokenLimits.check_limit(100_000, "anthropic:claude-3-5-sonnet") == :ok
    end

    test "returns {:warn, limit, threshold} when at threshold" do
      assert {:warn, 200_000, 0.8} =
               TokenLimits.check_limit(160_000, "anthropic:claude-3-5-sonnet")
    end

    test "returns :ok when just below threshold" do
      assert TokenLimits.check_limit(159_999, "anthropic:claude-3-5-sonnet") == :ok
    end

    test "returns :ok for unknown provider" do
      assert TokenLimits.check_limit(999_999, "unknown:model") == :ok
    end

    test "respects custom threshold" do
      original_threshold = Application.get_env(:ash_agent, :token_warning_threshold)

      try do
        Application.put_env(:ash_agent, :token_warning_threshold, 0.5)

        assert {:warn, 200_000, 0.5} =
                 TokenLimits.check_limit(100_000, "anthropic:claude-3-5-sonnet")

        assert TokenLimits.check_limit(99_999, "anthropic:claude-3-5-sonnet") == :ok
      after
        if original_threshold do
          Application.put_env(:ash_agent, :token_warning_threshold, original_threshold)
        else
          Application.delete_env(:ash_agent, :token_warning_threshold)
        end
      end
    end
  end
end
