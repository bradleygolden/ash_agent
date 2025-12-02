defmodule AshAgent.Integration.Thinking.ReqLLM.AnthropicTest do
  @moduledoc """
  Live API tests for thinking/reasoning content extraction with ReqLLM backend.

  Tests the ReqLLM capability matrix:

  ## Streaming
  | Capability               | ReqLLM |
  |--------------------------|--------|
  | Text                     | Yes    |
  | Structured               | No     |
  | With Thinking            | Yes    |
  | With Thinking+Structured | No     |

  ## Extended Thinking
  | Capability        | ReqLLM |
  |-------------------|--------|
  | Text Output       | Yes    |
  | Structured Output | No     |

  Requires ANTHROPIC_API_KEY environment variable.
  """
  use AshAgent.IntegrationCase, backend: :req_llm, provider: :anthropic

  alias AshAgent.Runtime

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule TextThinkingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.Thinking.ReqLLM.AnthropicTest.TestDomain,
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

  defmodule StructuredThinkingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.Thinking.ReqLLM.AnthropicTest.TestDomain,
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

  setup do
    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  describe "Extended Thinking - Text Output (Yes)" do
    test "call/2 returns text output with thinking content" do
      {:ok, result} = Runtime.call(TextThinkingAgent, %{question: "What is 15 + 27?"})

      assert %AshAgent.Result{} = result
      assert is_binary(result.output)
      assert is_binary(result.thinking), "Expected thinking content from reasoning model"
      assert String.length(result.thinking) > 0, "Expected non-empty thinking content"
    end
  end

  describe "Extended Thinking - Structured Output (No)" do
    @tag :skip
    @tag skip_reason:
           "Extended thinking requires tool_choice: auto, but ReqLLM structured output uses forced tool_choice"
    test "call/2 cannot return structured output with thinking" do
      {:ok, result} =
        Runtime.call(StructuredThinkingAgent, %{question: "What is 15 + 27?"})

      assert %AshAgent.Result{} = result
      assert %{answer: answer, explanation: explanation} = result.output
      assert is_integer(answer)
      assert is_binary(explanation)
    end
  end

  describe "Streaming - Text With Thinking (Yes)" do
    test "stream/2 yields thinking chunks and text content" do
      {:ok, stream} = Runtime.stream(TextThinkingAgent, %{question: "What is 2 + 2?"})

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

  describe "Streaming - Structured With Thinking (No)" do
    @tag :skip
    @tag skip_reason:
           "Extended thinking requires tool_choice: auto, but ReqLLM structured output uses forced tool_choice"
    test "stream/2 cannot yield structured output with thinking" do
      {:ok, stream} =
        Runtime.stream(StructuredThinkingAgent, %{question: "What is 10 + 5?"})

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
end
