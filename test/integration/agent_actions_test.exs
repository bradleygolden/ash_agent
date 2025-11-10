defmodule AshAgent.Integration.AgentActionsTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  if Code.ensure_loaded?(AshAgent.Test.OllamaClient.AgentReply) do
    alias Ash.Resource.Info
    alias AshAgent.Test.OllamaClient.AgentReply

    defmodule OllamaAgent do
      use Ash.Resource,
        domain: AshAgent.TestDomain,
        extensions: [AshAgent.Resource]

      resource do
        require_primary_key? false
      end

      agent do
        provider :baml
        client :ollama, function: :AgentEcho
        output AgentReply

        input do
          argument :message, :string, allow_nil?: false
        end
      end

      code_interface do
        define :call, args: [:message]
        define :stream, args: [:message]
      end
    end

    describe "generated actions" do
      test "mirror agent configuration" do
        call_action = Info.action(OllamaAgent, :call)
        stream_action = Info.action(OllamaAgent, :stream)

        assert AgentReply == call_action.returns
        assert {:array, AgentReply} == stream_action.returns

        assert [%{name: :message, type: :string}] ==
                 Enum.map(call_action.arguments, &%{name: &1.name, type: &1.type})

        assert [%{name: :message, type: :string}] ==
                 Enum.map(stream_action.arguments, &%{name: &1.name, type: &1.type})
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
        assert {:ok, %AgentReply{} = reply} = OllamaAgent.call("integration ping")
        assert String.starts_with?(reply.content, "integration")
        assert is_float(reply.confidence)
      end

      test "stream action emits structured payload" do
        input =
          OllamaAgent
          |> Ash.ActionInput.for_action(:stream, %{message: "stream integration"})

        assert {:ok, stream} = Ash.run_action(input)

        results =
          stream
          |> Enum.to_list()
          |> Enum.filter(&match?(%AgentReply{}, &1))

        assert [_ | _] = results
        reply = List.last(results)
        assert String.starts_with?(reply.content, "integration")
      end
    end
  end
end
