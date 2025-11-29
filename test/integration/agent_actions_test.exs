defmodule AshAgent.Integration.AgentActionsTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  if Code.ensure_loaded?(AshAgent.Test.OllamaClient) do
    alias Ash.Resource.Info

    defmodule OllamaAgent do
      use Ash.Resource,
        domain: AshAgent.TestDomain,
        extensions: [AshAgent.Resource]

      resource do
        require_primary_key? false
      end

      agent do
        provider :baml

        client AshAgent.Test.OllamaClient,
          function: :AgentEcho,
          client_module: AshAgent.Test.OllamaClient

        output_schema(
          Zoi.object(
            %{
              content: Zoi.string(),
              confidence: Zoi.float() |> Zoi.optional()
            },
            coerce: true
          )
        )
      end

      code_interface do
        define :call, args: [:input]
        define :stream, args: [:input]
      end
    end

    describe "generated actions" do
      test "mirror agent configuration" do
        call_action = Info.action(OllamaAgent, :call)
        stream_action = Info.action(OllamaAgent, :stream)

        assert :map == call_action.returns
        assert {:array, :map} == stream_action.returns
      end

      test "context attribute is automatically added" do
        context_attr = Info.attribute(OllamaAgent, :context)

        assert %Ash.Resource.Attribute{} = context_attr
        assert context_attr.name == :context
        assert context_attr.type == AshAgent.Context
        assert context_attr.allow_nil? == true
        assert context_attr.public? == true
      end
    end

    describe "agent execution" do
      test "code interface call reaches ollama" do
        assert {:ok, reply} = OllamaAgent.call(%{message: "integration ping"})
        assert is_map(reply)
        assert is_binary(reply.content)
      end

      test "stream action emits structured payload" do
        input =
          OllamaAgent
          |> Ash.ActionInput.for_action(:stream, %{input: %{message: "stream integration"}})

        assert {:ok, stream} = Ash.run_action(input)

        results =
          stream
          |> Enum.to_list()
          |> Enum.filter(&is_map/1)

        assert [_ | _] = results
        reply = List.last(results)
        assert is_binary(reply.content)
      end
    end
  end
end
