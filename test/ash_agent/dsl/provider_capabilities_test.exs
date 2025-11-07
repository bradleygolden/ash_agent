defmodule AshAgent.DSL.ProviderCapabilitiesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defmodule Output do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :content, :string
    end
  end

  setup do
    original_clients = Application.get_env(:ash_baml, :clients)

    Application.put_env(:ash_baml, :clients, support: {AshAgent.Test.BamlClient, []})

    on_exit(fn ->
      Application.put_env(:ash_baml, :clients, original_clients)
    end)

    :ok
  end

  test "raises when provider lacks tool_calling feature" do
    message =
      capture_io(:stderr, fn ->
        assert_raise Spark.Error.DslError, fn ->
          defmodule NoToolProviderAgent do
            use Ash.Resource,
              extensions: [AshAgent.Resource]

            agent do
              provider(:mock)
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
      end)

    assert message =~ "does not support tool calling"
  end

  test "allows promptless providers while enforcing prompts elsewhere" do
    assert_raise Spark.Error.DslError, fn ->
      defmodule MissingPromptAgent do
        use Ash.Resource,
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
