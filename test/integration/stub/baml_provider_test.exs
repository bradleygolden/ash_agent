defmodule AshAgent.Integration.Stub.BamlProviderTest do
  @moduledoc false
  use AshAgent.IntegrationCase

  alias AshAgent.Runtime

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
      domain: AshAgent.Integration.Stub.BamlProviderTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider(:baml)

      client AshAgent.Test.BamlClient,
        function: :ChatAgent,
        client_module: AshAgent.Test.BamlClient

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{content: Zoi.string()}, coerce: true))
      instruction("Test")
    end
  end

  describe "call/2 with :baml provider" do
    test "delegates to configured BAML function" do
      assert {:ok, %AshAgent.Result{output: %{content: "BAML reply: hello"}}} =
               Runtime.call(TestAgent, message: "hello")
    end
  end

  describe "stream/2 with :baml provider" do
    test "wraps BAML streaming into Elixir stream" do
      assert {:ok, stream} = Runtime.stream(TestAgent, message: "one two")

      chunks = Enum.to_list(stream)
      content_chunks = Enum.filter(chunks, &match?({:content, _}, &1))
      assert Enum.any?(content_chunks, &match?({:content, %{content: "one"}}, &1))
      assert {:done, %AshAgent.Result{output: %{content: "one two"}}} = List.last(chunks)
    end
  end

  describe "metadata extraction with :baml provider" do
    test "Result.metadata is populated with Metadata struct" do
      {:ok, result} = Runtime.call(TestAgent, message: "test")

      assert %AshAgent.Metadata{} = result.metadata
      assert result.metadata.provider == :baml
    end

    test "metadata contains timing fields from runtime" do
      {:ok, result} = Runtime.call(TestAgent, message: "test")

      assert %DateTime{} = result.metadata.started_at
      assert %DateTime{} = result.metadata.completed_at
      assert is_integer(result.metadata.duration_ms)
      assert result.metadata.duration_ms >= 0
    end

    test "metadata is JSON-serializable" do
      {:ok, result} = Runtime.call(TestAgent, message: "test")

      assert {:ok, json} = Jason.encode(result.metadata)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["provider"] == "baml"
    end

    test "streaming result includes metadata struct" do
      {:ok, stream} = Runtime.stream(TestAgent, message: "test")
      chunks = Enum.to_list(stream)
      {:done, result} = List.last(chunks)

      assert %AshAgent.Metadata{} = result.metadata
    end

    test "streaming result includes timing metadata" do
      {:ok, stream} = Runtime.stream(TestAgent, message: "test")
      chunks = Enum.to_list(stream)
      {:done, result} = List.last(chunks)

      assert %DateTime{} = result.metadata.started_at
      assert %DateTime{} = result.metadata.completed_at
      assert is_integer(result.metadata.duration_ms)
    end
  end
end
