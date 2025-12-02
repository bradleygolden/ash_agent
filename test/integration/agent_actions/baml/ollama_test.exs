defmodule AshAgent.Integration.AgentActions.BAML.OllamaTest do
  @moduledoc false
  use AshAgent.IntegrationCase, backend: :baml, provider: :ollama

  if Code.ensure_loaded?(AshAgent.Test.OllamaClient) do
    alias Ash.Resource.Info

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
        domain: AshAgent.Integration.AgentActions.BAML.OllamaTest.TestDomain,
        extensions: [AshAgent.Resource]

      resource do
        require_primary_key? false
      end

      agent do
        provider :baml

        client AshAgent.Test.OllamaClient,
          function: :AgentEcho,
          client_module: AshAgent.Test.OllamaClient

        input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))

        output_schema(
          Zoi.object(
            %{
              content: Zoi.string(),
              confidence: Zoi.float() |> Zoi.optional()
            },
            coerce: true
          )
        )

        instruction("Test")
      end
    end

    describe "generated actions" do
      test "mirror agent configuration" do
        call_action = Info.action(TestAgent, :call)
        stream_action = Info.action(TestAgent, :stream)

        assert :map == call_action.returns
        assert {:array, :map} == stream_action.returns
      end
    end

    describe "agent execution" do
      test "Runtime.call reaches ollama" do
        assert {:ok, %AshAgent.Result{output: reply}} =
                 AshAgent.Runtime.call(TestAgent, %{message: "integration ping"})

        assert is_map(reply)
        assert is_binary(reply.content)
      end

      test "Runtime.stream emits structured payload" do
        assert {:ok, stream} =
                 AshAgent.Runtime.stream(TestAgent, %{message: "stream integration"})

        results =
          stream
          |> Enum.to_list()
          |> Enum.filter(fn
            {:content, _} -> true
            {:done, _} -> true
            _ -> false
          end)
          |> Enum.map(fn
            {:content, data} -> data
            {:done, %AshAgent.Result{output: data}} -> data
          end)

        assert [_ | _] = results
        reply = List.last(results)
        assert is_binary(reply.content)
      end
    end
  end
end
