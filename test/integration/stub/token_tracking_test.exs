defmodule AshAgent.Integration.Stub.TokenTrackingTest do
  @moduledoc false
  use AshAgent.IntegrationCase

  alias AshAgent.Runtime
  alias AshAgent.Test.LLMStub

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule TokenTrackingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.Stub.TokenTrackingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
      instruction("Test prompt")
    end
  end

  describe "token tracking integration" do
    test "handles nil usage gracefully (BAML provider)" do
      Req.Test.expect(AshAgent.LLMStub, fn conn ->
        Req.Test.json(conn, %{
          "id" => "msg_test",
          "type" => "message",
          "role" => "assistant",
          "content" => [
            %{
              "type" => "tool_use",
              "id" => "toolu_test",
              "name" => "structured_output",
              "input" => %{"result" => "Success"}
            }
          ],
          "model" => "claude-3-5-sonnet-20241022",
          "stop_reason" => "tool_use"
        })
      end)

      Req.Test.expect(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Success"})
      )

      assert {:ok, %AshAgent.Result{output: %{result: "Success"}}} =
               Runtime.call(TokenTrackingAgent, %{})
    end

    test "LLM response with usage data gets tracked" do
      Req.Test.expect(
        AshAgent.LLMStub,
        2,
        LLMStub.object_response(%{"result" => "Success with tokens"})
      )

      parent = self()
      handler_id = {:token_tracking_test, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ash_agent, :call, :stop],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, metadata})
        end,
        nil
      )

      try do
        assert {:ok, %AshAgent.Result{output: %{result: "Success with tokens"}}} =
                 Runtime.call(TokenTrackingAgent, %{})

        metadata =
          receive do
            {:telemetry, %{agent: TokenTrackingAgent} = meta} -> meta
            _other -> flunk("received unexpected telemetry payload")
          after
            1000 -> flunk("did not receive telemetry for TokenTrackingAgent")
          end

        assert metadata.status == :ok
        assert metadata.usage.input_tokens == 10
        assert metadata.usage.output_tokens == 20
      after
        :telemetry.detach(handler_id)
      end
    end

    test "does not emit warning when below threshold" do
      Req.Test.expect(
        AshAgent.LLMStub,
        2,
        LLMStub.object_response(%{"result" => "Low usage"})
      )

      parent = self()
      handler_id = {:no_warning_test, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ash_agent, :token_limit_warning],
        fn event, measurements, metadata, _ ->
          send(parent, {:warning, event, measurements, metadata})
        end,
        nil
      )

      try do
        assert {:ok, %AshAgent.Result{output: %{result: "Low usage"}}} =
                 Runtime.call(TokenTrackingAgent, %{})

        refute_receive {:warning, _, _, _}, 100
      after
        :telemetry.detach(handler_id)
      end
    end
  end
end
