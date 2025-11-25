defmodule AshAgent.Providers.BamlProviderTest do
  @moduledoc false
  use ExUnit.Case, async: true
  @moduletag :integration

  alias AshAgent.Runtime
  alias AshAgent.Test.BamlClient.Reply

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
      # Use direct module reference instead of configured client identifier
      # This avoids coupling to ash_baml's application configuration
      client AshAgent.Test.BamlClient,
        function: :ChatAgent,
        client_module: AshAgent.Test.BamlClient

      output Reply

      input do
        argument :message, :string
      end
    end
  end

  describe "call/2 with :baml provider" do
    test "delegates to configured BAML function" do
      assert {:ok, %Reply{content: "BAML reply: hello"}} =
               Runtime.call(Agent, message: "hello")
    end
  end

  describe "stream/2 with :baml provider" do
    test "wraps BAML streaming into Elixir stream" do
      assert {:ok, stream} = Runtime.stream(Agent, message: "one two")

      chunks = Enum.to_list(stream)
      assert Enum.any?(chunks, &match?(%Reply{content: "one"}, &1))
      assert List.last(chunks) == %Reply{content: "one two"}
    end
  end
end
