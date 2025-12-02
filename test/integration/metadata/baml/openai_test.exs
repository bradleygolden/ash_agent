defmodule AshAgent.Integration.Metadata.BAML.OpenAITest do
  @moduledoc false
  use AshAgent.IntegrationCase, backend: :baml, provider: :openai

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
      domain: AshAgent.Integration.Metadata.BAML.OpenAITest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :baml

      client AshAgent.Test.OpenAIBamlClient,
        function: :MetadataTest,
        client_module: AshAgent.Test.OpenAIBamlClient

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{response: Zoi.string()}, coerce: true))
      instruction("Reply with response")
    end
  end

  test "result has Metadata struct" do
    {:ok, result} = Runtime.call(TestAgent, %{message: "say hi"})

    assert %Metadata{} = result.metadata
    assert result.metadata.provider == :baml
  end

  test "metadata has timing" do
    {:ok, result} = Runtime.call(TestAgent, %{message: "say hello"})

    assert %DateTime{} = result.metadata.started_at
    assert %DateTime{} = result.metadata.completed_at
    assert is_integer(result.metadata.duration_ms)
    assert result.metadata.duration_ms >= 0
  end

  test "metadata is JSON-serializable" do
    {:ok, result} = Runtime.call(TestAgent, %{message: "hi there"})

    assert {:ok, json} = Jason.encode(result.metadata)
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["provider"] == "baml"
  end
end
