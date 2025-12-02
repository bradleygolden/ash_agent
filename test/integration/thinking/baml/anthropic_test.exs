defmodule AshAgent.Integration.Thinking.BAML.AnthropicTest do
  @moduledoc """
  Live API tests for thinking/reasoning content extraction with BAML backend.

  Tests the BAML capability matrix:

  ## Streaming
  | Capability               | BAML |
  |--------------------------|------|
  | Text                     | Yes  |
  | Structured               | Yes  |
  | With Thinking            | No   |
  | With Thinking+Structured | No   |

  ## Extended Thinking
  | Capability        | BAML |
  |-------------------|------|
  | Text Output       | Yes  |
  | Structured Output | Yes  |

  Requires ANTHROPIC_API_KEY environment variable.
  """
  use AshAgent.IntegrationCase, backend: :baml, provider: :anthropic

  alias AshAgent.Runtime

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule StructuredThinkingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.Thinking.BAML.AnthropicTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :baml

      client :thinking, function: :SolveWithThinking

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{answer: Zoi.integer(), explanation: Zoi.string()}, coerce: true))
      instruction("BAML function")
    end
  end

  defmodule TextThinkingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.Thinking.BAML.AnthropicTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :baml

      client :thinking, function: :AnswerWithThinking

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(:string)
      instruction("BAML function")
    end
  end

  describe "Extended Thinking - Text Output (Yes)" do
    test "call/2 returns text output with thinking content" do
      {:ok, result} = Runtime.call(TextThinkingAgent, %{question: "What is 15 + 27?"})

      assert %AshAgent.Result{} = result
      assert is_binary(result.output)
      assert is_binary(result.thinking), "Expected thinking content from BAML"
      assert String.length(result.thinking) > 0, "Expected non-empty thinking content"
    end
  end

  describe "Extended Thinking - Structured Output (Yes)" do
    test "call/2 returns structured output AND thinking content" do
      {:ok, result} = Runtime.call(StructuredThinkingAgent, %{question: "What is 15 + 27?"})

      assert %AshAgent.Result{} = result
      assert %{answer: answer, explanation: explanation} = result.output
      assert is_integer(answer)
      assert is_binary(explanation)

      assert is_binary(result.thinking),
             "Expected thinking content - BAML uses SAP not tool_choice"

      assert String.length(result.thinking) > 0, "Expected non-empty thinking content"
    end
  end

  describe "Streaming - Text With Thinking (No)" do
    @tag :skip
    @tag skip_reason:
           "baml_elixir streaming doesn't expose HTTP response body in collector - thinking unavailable"
    test "stream/2 yields text but thinking is not available" do
      {:ok, stream} = Runtime.stream(TextThinkingAgent, %{question: "What is 2 + 2?"})

      chunks = Enum.to_list(stream)

      done_chunks = Enum.filter(chunks, &match?({:done, _}, &1))

      assert length(done_chunks) == 1, "Expected exactly one done chunk"

      {:done, result} = List.last(done_chunks)
      assert %AshAgent.Result{} = result
      assert is_binary(result.output), "Expected text output"
      assert is_binary(result.thinking), "Expected thinking in final result"
      assert String.length(result.thinking) > 0, "Expected non-empty thinking content"
    end
  end

  describe "Streaming - Structured With Thinking (No)" do
    alias AshAgent.Test.ThinkingBamlClient.Types.MathAnswer

    @tag :skip
    @tag skip_reason:
           "baml_elixir streaming doesn't expose HTTP response body in collector - thinking unavailable"
    test "stream/2 yields structured output but thinking is not available" do
      {:ok, stream} = Runtime.stream(StructuredThinkingAgent, %{question: "What is 10 + 5?"})

      chunks = Enum.to_list(stream)

      done_chunks = Enum.filter(chunks, &match?({:done, _}, &1))

      assert length(done_chunks) == 1, "Expected exactly one done chunk"

      {:done, result} = List.last(done_chunks)
      assert %AshAgent.Result{} = result
      assert %MathAnswer{answer: answer} = result.output
      assert is_integer(answer)
      assert is_binary(result.thinking), "Expected thinking in final result"
      assert String.length(result.thinking) > 0, "Expected non-empty thinking content"
    end
  end
end
