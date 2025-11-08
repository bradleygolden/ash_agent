defmodule AshAgent.DSL.ProviderCapabilitiesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  defmodule Output do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :content, :string
    end
  end

  defmodule NoToolProvider do
    @behaviour AshAgent.Provider

    @impl true
    def call(_, _, _, _, _, _, _), do: {:ok, %{}}

    @impl true
    def stream(_, _, _, _, _, _, _), do: {:ok, []}

    @impl true
    def introspect do
      %{
        provider: :no_tools,
        features: [:sync_call]
      }
    end
  end

  setup do
    original_clients = Application.get_env(:ash_baml, :clients)
    original_providers = Application.get_env(:ash_agent, :providers)

    Application.put_env(:ash_baml, :clients, support: {AshAgent.Test.BamlClient, []})
    updated_providers = Keyword.put(original_providers || [], :no_tools, NoToolProvider)
    Application.put_env(:ash_agent, :providers, updated_providers)

    on_exit(fn ->
      Application.put_env(:ash_baml, :clients, original_clients)
      Application.put_env(:ash_agent, :providers, original_providers)
    end)

    :ok
  end

  test "raises when provider lacks tool_calling feature" do
    error =
      assert_raise Spark.Error.DslError, fn ->
        defmodule NoToolProviderAgent do
          use Ash.Resource,
            domain: AshAgent.TestDomain,
            extensions: [AshAgent.Resource]

          agent do
            provider(:no_tools)
            client "anthropic:claude-3-5-sonnet"
            output Output
            prompt "Testing"
          end

          tools do
            tool :foo do
              description "foo"
              function({Kernel, :self, []})
              parameters([])
            end
          end
        end
      end

    assert Exception.message(error) =~ "does not support tool calling"
  end

  test "allows promptless providers while enforcing prompts elsewhere" do
    assert_raise Spark.Error.DslError, fn ->
      defmodule MissingPromptAgent do
        use Ash.Resource,
          domain: AshAgent.TestDomain,
          extensions: [AshAgent.Resource]

        agent do
          provider(:req_llm)
          client "anthropic:claude-3-5-sonnet"
          output Output
        end
      end
    end

    defmodule PromptlessBamlAgent do
      use Ash.Resource,
        domain: AshAgent.TestDomain,
        extensions: [AshAgent.Resource]

      agent do
        provider :baml
        client :support, function: :ChatAgent
        output Output
      end
    end

    assert PromptlessBamlAgent
  end
end
