defmodule AshAgent.Integration.Metadata.ReqLLM.OpenRouterTest do
  @moduledoc false
  use AshAgent.IntegrationCase, backend: :req_llm, provider: :openrouter

  alias AshAgent.{Metadata, Runtime}

  setup do
    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule TestAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.Metadata.ReqLLM.OpenRouterTest.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client("openrouter:x-ai/grok-4.1-fast:free", temperature: 0.0, max_tokens: 100)

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{response: Zoi.string()}, coerce: true))

      instruction(~p"""
      Reply with JSON matching the output format exactly.
      {{ ctx.output_format }}
      Message: {{ message }}
      """)
    end
  end

  test "extracts usage from OpenRouter response" do
    {:ok, result} = Runtime.call(TestAgent, %{message: "say hi"})

    assert is_map(result.usage)
    assert result.usage[:input_tokens] > 0
    assert result.usage[:output_tokens] > 0
  end

  test "extracts model identifier from OpenRouter" do
    {:ok, result} = Runtime.call(TestAgent, %{message: "say hi"})

    assert is_binary(result.model)
  end

  test "result has Metadata struct" do
    {:ok, result} = Runtime.call(TestAgent, %{message: "say hi"})

    assert %Metadata{} = result.metadata
    assert result.metadata.provider == :req_llm
  end

  test "metadata is JSON-serializable" do
    {:ok, result} = Runtime.call(TestAgent, %{message: "say hi"})

    state = %{
      output: result.output,
      usage: result.usage,
      model: result.model,
      metadata: Map.from_struct(result.metadata)
    }

    assert {:ok, _json} = Jason.encode(state)
  end

  test "result has timing metadata" do
    {:ok, result} = Runtime.call(TestAgent, %{message: "say hi"})

    assert %DateTime{} = result.metadata.started_at
    assert %DateTime{} = result.metadata.completed_at
    assert is_integer(result.metadata.duration_ms)
    assert result.metadata.duration_ms >= 0
  end
end
