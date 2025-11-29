defmodule AshAgent.TokenTrackingTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias AshAgent.Context
  alias AshAgent.Runtime
  alias AshAgent.Test.LLMStub

  defmodule TokenTrackingAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.TokenTrackingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
      prompt "Test prompt"
    end
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
      resource TokenTrackingAgent
    end
  end

  describe "token tracking integration" do
    test "Context stores token usage from LLM response" do
      context = Context.new("Hello", [])

      usage = %{
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150
      }

      updated_context = Context.add_token_usage(context, usage)

      iteration = Context.get_iteration(updated_context, 1)
      assert iteration.metadata.current_usage == usage
      assert iteration.metadata.cumulative_tokens.input_tokens == 100
      assert iteration.metadata.cumulative_tokens.output_tokens == 50
      assert iteration.metadata.cumulative_tokens.total_tokens == 150
    end

    test "cumulative tokens accumulate across multiple LLM calls" do
      context = Context.new("Hello", [])

      usage1 = %{input_tokens: 100, output_tokens: 50, total_tokens: 150}
      usage2 = %{input_tokens: 75, output_tokens: 25, total_tokens: 100}
      usage3 = %{input_tokens: 50, output_tokens: 30, total_tokens: 80}

      context = Context.add_token_usage(context, usage1)
      context = Context.add_token_usage(context, usage2)
      context = Context.add_token_usage(context, usage3)

      cumulative = Context.get_cumulative_tokens(context)
      assert cumulative.input_tokens == 225
      assert cumulative.output_tokens == 105
      assert cumulative.total_tokens == 330
    end

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
