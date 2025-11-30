defmodule AshAgent.Integration.ReqLLMIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  setup_all do
    ReqLLM.put_key(:openai_api_key, "ollama")
    :ok
  end

  setup do
    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  defmodule ReqLLMAgent do
    use Ash.Resource,
      domain: AshAgent.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client("openai:qwen3:1.7b",
        base_url: "http://localhost:11434/v1",
        api_key: "ollama",
        temperature: 0.0
      )

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))

      output_schema(
        Zoi.object(
          %{
            content: Zoi.string(),
            confidence: Zoi.float()
          },
          coerce: true
        )
      )

      instruction(~p"""
      Reply with JSON matching ctx.output_format exactly.
      content must start with "req integration:" followed by the message.
      confidence must be 0.99.
      Message: {{ message }}
      {{ ctx.output_format }}
      """)
    end
  end

  describe "req_llm provider against Ollama" do
    test "Runtime.call reaches local LLM" do
      assert {:ok, %AshAgent.Result{output: reply}} =
               AshAgent.Runtime.call(ReqLLMAgent, %{message: "ping"})

      assert is_map(reply)
      assert String.starts_with?(reply.content, "req integration")
      assert reply.confidence == 0.99
    end

    test "Runtime.call uses same pipeline" do
      assert {:ok, %AshAgent.Result{output: reply}} =
               AshAgent.Runtime.call(ReqLLMAgent, %{message: "from action"})

      assert is_map(reply)
      assert is_binary(reply.content)
      assert is_float(reply.confidence)
    end
  end
end
