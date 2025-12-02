defmodule AshAgent.Integration.Metadata.BAML.AnthropicTest do
  @moduledoc false
  use AshAgent.IntegrationCase, backend: :baml, provider: :anthropic

  alias AshAgent.{Metadata, Runtime}

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
      domain: AshAgent.Integration.Metadata.BAML.AnthropicTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :baml

      client AshAgent.Test.ThinkingBamlClient,
        function: :SolveWithThinking,
        client_module: AshAgent.Test.ThinkingBamlClient

      input_schema(Zoi.object(%{question: Zoi.string()}, coerce: true))

      output_schema(Zoi.object(%{answer: Zoi.integer(), explanation: Zoi.string()}, coerce: true))

      instruction("Solve math")
    end
  end

  test "result has Metadata struct" do
    {:ok, result} = Runtime.call(TestAgent, %{question: "What is 2+2?"})

    assert %Metadata{} = result.metadata
    assert result.metadata.provider == :baml
  end

  test "metadata has timing" do
    {:ok, result} = Runtime.call(TestAgent, %{question: "What is 1+1?"})

    assert %DateTime{} = result.metadata.started_at
    assert %DateTime{} = result.metadata.completed_at
    assert is_integer(result.metadata.duration_ms)
    assert result.metadata.duration_ms >= 0
  end

  test "metadata is JSON-serializable" do
    {:ok, result} = Runtime.call(TestAgent, %{question: "What is 3+3?"})

    assert {:ok, json} = Jason.encode(result.metadata)
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["provider"] == "baml"
  end
end
