defmodule AshAgent.Providers.BamlProviderTest do
  @moduledoc false
  use ExUnit.Case, async: true
  @moduletag :integration

  alias AshAgent.Runtime

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshAgent.Providers.BamlProviderTest.Agent
    end
  end

  defmodule Agent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Providers.BamlProviderTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider(:baml)

      client AshAgent.Test.BamlClient,
        function: :ChatAgent,
        client_module: AshAgent.Test.BamlClient

      output_schema(Zoi.object(%{content: Zoi.string()}, coerce: true))
    end
  end

  describe "call/2 with :baml provider" do
    test "delegates to configured BAML function" do
      assert {:ok, %AshAgent.Result{output: %{content: "BAML reply: hello"}}} =
               Runtime.call(Agent, message: "hello")
    end
  end

  describe "stream/2 with :baml provider" do
    test "wraps BAML streaming into Elixir stream" do
      assert {:ok, stream} = Runtime.stream(Agent, message: "one two")

      chunks = Enum.to_list(stream)
      content_chunks = Enum.filter(chunks, &match?({:content, _}, &1))
      assert Enum.any?(content_chunks, &match?({:content, %{content: "one"}}, &1))
      assert {:done, %AshAgent.Result{output: %{content: "one two"}}} = List.last(chunks)
    end
  end
end
