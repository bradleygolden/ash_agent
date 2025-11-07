defmodule AshAgent.Providers.BamlProviderTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias AshAgent.Runtime
  alias AshAgent.Test.BamlClient.Reply

  setup do
    original_clients = Application.get_env(:ash_baml, :clients)

    Application.put_env(:ash_baml, :clients, support: {AshAgent.Test.BamlClient, []})

    on_exit(fn ->
      Application.put_env(:ash_baml, :clients, original_clients)
    end)

    :ok
  end

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

    agent do
      provider(:baml)
      client :support, function: :ChatAgent
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
