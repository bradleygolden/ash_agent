defmodule AshAgent.ResultTest do
  @moduledoc """
  Unit tests for AshAgent.Result struct.
  """
  use ExUnit.Case, async: true

  alias AshAgent.Result

  describe "struct definition" do
    test "has expected fields with default values" do
      result = %Result{}

      assert result.output == nil
      assert result.thinking == nil
      assert result.usage == nil
      assert result.model == nil
      assert result.finish_reason == nil
      assert result.metadata == %{}
      assert result.raw_response == nil
    end

    test "accepts all fields" do
      result = %Result{
        output: %{content: "test"},
        thinking: "reasoning...",
        usage: %{input_tokens: 10, output_tokens: 5},
        model: "claude-3-5-sonnet",
        finish_reason: :stop,
        metadata: %{custom: "value"},
        raw_response: %{raw: "data"}
      }

      assert result.output == %{content: "test"}
      assert result.thinking == "reasoning..."
      assert result.usage == %{input_tokens: 10, output_tokens: 5}
      assert result.model == "claude-3-5-sonnet"
      assert result.finish_reason == :stop
      assert result.metadata == %{custom: "value"}
      assert result.raw_response == %{raw: "data"}
    end
  end

  describe "type specification" do
    test "implements the t type" do
      result = %Result{output: "test"}

      assert %Result{} = result
    end
  end

  describe "common usage patterns" do
    test "can wrap a simple output" do
      output = %{message: "Hello"}
      result = %Result{output: output}

      assert result.output.message == "Hello"
    end

    test "can store thinking content from extended thinking" do
      result = %Result{
        output: %{content: "final answer"},
        thinking: "Let me think about this step by step..."
      }

      assert result.thinking =~ "step by step"
    end

    test "can store usage metadata" do
      result = %Result{
        output: %{},
        usage: %{
          input_tokens: 100,
          output_tokens: 50,
          total_tokens: 150
        }
      }

      assert result.usage[:input_tokens] == 100
      assert result.usage[:output_tokens] == 50
    end

    test "finish_reason can be atom" do
      result = %Result{finish_reason: :stop}
      assert result.finish_reason == :stop

      result = %Result{finish_reason: :length}
      assert result.finish_reason == :length

      result = %Result{finish_reason: :tool_use}
      assert result.finish_reason == :tool_use
    end

    test "metadata map is extensible" do
      result = %Result{
        output: %{},
        metadata: %{
          request_id: "req_123",
          latency_ms: 150,
          custom_field: "anything"
        }
      }

      assert result.metadata.request_id == "req_123"
      assert result.metadata.latency_ms == 150
      assert result.metadata.custom_field == "anything"
    end
  end
end
