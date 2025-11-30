defmodule AshAgent.Integration.ThinkingTest do
  @moduledoc """
  Live API tests for thinking/reasoning content extraction.

  These tests prove the capability matrix documented in README.md:

  ## Streaming
  | Capability               | ReqLLM | BAML |
  |--------------------------|--------|------|
  | Text                     | Yes    | Yes  |
  | Structured               | No     | Yes  |
  | With Thinking            | Yes    | No   |
  | With Thinking+Structured | No     | No   |

  ## Extended Thinking
  | Capability        | ReqLLM | BAML |
  |-------------------|--------|------|
  | Text Output       | Yes    | Yes  |
  | Structured Output | No     | Yes  |

  Requires ANTHROPIC_API_KEY environment variable.
  Run with: mix test --only live
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :live

  alias AshAgent.Runtime

  defmodule ReqLlmTextThinkingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.ThinkingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :req_llm

      client "anthropic:claude-haiku-4-5-20251001",
        max_tokens: 16_000,
        provider_options: [thinking: %{type: "enabled", budget_tokens: 5000}]

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(:string)

      instruction("Answer briefly: {{ question }}")
    end
  end

  defmodule ReqLlmStructuredThinkingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.ThinkingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :req_llm

      client "anthropic:claude-haiku-4-5-20251001",
        max_tokens: 16_000,
        provider_options: [thinking: %{type: "enabled", budget_tokens: 5000}]

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{answer: Zoi.integer(), explanation: Zoi.string()}, coerce: true))

      instruction(
        "Solve the math problem and provide the numeric answer with a brief explanation: {{ question }}"
      )
    end
  end

  defmodule BamlStructuredThinkingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.ThinkingTest.TestDomain,
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

  defmodule BamlTextThinkingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.ThinkingTest.TestDomain,
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

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
      resource ReqLlmTextThinkingAgent
      resource ReqLlmStructuredThinkingAgent
      resource BamlStructuredThinkingAgent
      resource BamlTextThinkingAgent
    end
  end

  setup do
    unless System.get_env("ANTHROPIC_API_KEY") do
      raise "ANTHROPIC_API_KEY environment variable required for live tests"
    end

    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  describe "ReqLLM Extended Thinking - Text Output (Yes)" do
    test "call/2 returns text output with thinking content" do
      {:ok, result} = Runtime.call(ReqLlmTextThinkingAgent, %{question: "What is 15 + 27?"})

      assert %AshAgent.Result{} = result
      assert is_binary(result.output)
      assert is_binary(result.thinking), "Expected thinking content from reasoning model"
      assert String.length(result.thinking) > 0, "Expected non-empty thinking content"
    end
  end

  describe "ReqLLM Extended Thinking - Structured Output (No)" do
    @tag :skip
    @tag skip_reason:
           "Extended thinking requires tool_choice: auto, but ReqLLM structured output uses forced tool_choice"
    test "call/2 cannot return structured output with thinking" do
      {:ok, result} =
        Runtime.call(ReqLlmStructuredThinkingAgent, %{question: "What is 15 + 27?"})

      assert %AshAgent.Result{} = result
      assert %{answer: answer, explanation: explanation} = result.output
      assert is_integer(answer)
      assert is_binary(explanation)
    end
  end

  describe "ReqLLM Streaming - Text With Thinking (Yes)" do
    test "stream/2 yields thinking chunks and text content" do
      {:ok, stream} = Runtime.stream(ReqLlmTextThinkingAgent, %{question: "What is 2 + 2?"})

      chunks = Enum.to_list(stream)

      thinking_chunks = Enum.filter(chunks, &match?({:thinking, _}, &1))
      content_chunks = Enum.filter(chunks, &match?({:content, _}, &1))
      done_chunks = Enum.filter(chunks, &match?({:done, _}, &1))

      assert length(thinking_chunks) > 0, "Expected thinking chunks from reasoning model"
      assert length(content_chunks) > 0, "Expected content chunks"
      assert length(done_chunks) == 1, "Expected exactly one done chunk"

      {:done, result} = List.last(done_chunks)
      assert %AshAgent.Result{} = result
      assert is_binary(result.output), "Expected output in final result"
      assert is_binary(result.thinking), "Expected accumulated thinking in final result"
    end
  end

  describe "ReqLLM Streaming - Structured With Thinking (No)" do
    @tag :skip
    @tag skip_reason:
           "Extended thinking requires tool_choice: auto, but ReqLLM structured output uses forced tool_choice"
    test "stream/2 cannot yield structured output with thinking" do
      {:ok, stream} =
        Runtime.stream(ReqLlmStructuredThinkingAgent, %{question: "What is 10 + 5?"})

      chunks = Enum.to_list(stream)

      content_chunks = Enum.filter(chunks, &match?({:content, _}, &1))
      done_chunks = Enum.filter(chunks, &match?({:done, _}, &1))

      assert length(content_chunks) > 0, "Expected content chunks"
      assert length(done_chunks) == 1, "Expected exactly one done chunk"

      {:done, result} = List.last(done_chunks)
      assert %AshAgent.Result{} = result
      assert %{answer: _, explanation: _} = result.output
    end
  end

  describe "BAML Extended Thinking - Text Output (Yes)" do
    test "call/2 returns text output with thinking content" do
      {:ok, result} = Runtime.call(BamlTextThinkingAgent, %{question: "What is 15 + 27?"})

      assert %AshAgent.Result{} = result
      assert is_binary(result.output)
      assert is_binary(result.thinking), "Expected thinking content from BAML"
      assert String.length(result.thinking) > 0, "Expected non-empty thinking content"
    end
  end

  describe "BAML Extended Thinking - Structured Output (Yes)" do
    test "call/2 returns structured output AND thinking content" do
      {:ok, result} = Runtime.call(BamlStructuredThinkingAgent, %{question: "What is 15 + 27?"})

      assert %AshAgent.Result{} = result
      assert %{answer: answer, explanation: explanation} = result.output
      assert is_integer(answer)
      assert is_binary(explanation)

      assert is_binary(result.thinking),
             "Expected thinking content - BAML uses SAP not tool_choice"

      assert String.length(result.thinking) > 0, "Expected non-empty thinking content"
    end
  end

  describe "BAML Streaming - Text With Thinking (No)" do
    @tag :skip
    @tag skip_reason:
           "baml_elixir streaming doesn't expose HTTP response body in collector - thinking unavailable"
    test "stream/2 yields text but thinking is not available" do
      {:ok, stream} = Runtime.stream(BamlTextThinkingAgent, %{question: "What is 2 + 2?"})

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

  describe "BAML Streaming - Structured With Thinking (No)" do
    alias AshAgent.Test.ThinkingBamlClient.Types.MathAnswer

    @tag :skip
    @tag skip_reason:
           "baml_elixir streaming doesn't expose HTTP response body in collector - thinking unavailable"
    test "stream/2 yields structured output but thinking is not available" do
      {:ok, stream} = Runtime.stream(BamlStructuredThinkingAgent, %{question: "What is 10 + 5?"})

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
