defmodule AshAgent.RuntimeTest do
  @moduledoc """
  Unit tests for AshAgent.Runtime module.

  Tests runtime execution without integration testing - focuses on internal logic.
  """
  use ExUnit.Case, async: true

  alias AshAgent.Error
  alias AshAgent.Runtime
  alias AshAgent.Test.LLMStub

  defmodule TestOutput do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :result, :string, allow_nil?: false
    end
  end

  defmodule MinimalAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
      extensions: [AshAgent.Resource]

    agent do
      client "anthropic:claude-3-5-sonnet"
      output TestOutput
      prompt "Test prompt"
    end
  end

  defmodule AgentWithArgs do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
      extensions: [AshAgent.Resource]

    agent do
      client "anthropic:claude-3-5-sonnet"
      output TestOutput
      prompt "Process: {{ input }}"

      input do
        argument :input, :string
      end
    end
  end

  defmodule AgentWithHooks do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
      extensions: [AshAgent.Resource]

    defmodule TestHooks do
      @moduledoc false
      @behaviour AshAgent.Runtime.Hooks

      def before_call(context) do
        send(self(), {:before_call, context.input})
        {:ok, context}
      end

      def after_render(context) do
        send(self(), {:after_render, context.rendered_prompt})
        {:ok, context}
      end

      def after_call(context) do
        send(self(), {:after_call, context.response})
        {:ok, context}
      end

      def on_error(context) do
        send(self(), {:on_error, context.error})
        {:ok, context}
      end
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      output TestOutput
      prompt "Test with hooks"
      hooks(TestHooks)
    end
  end

  defmodule NilOutputAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
      extensions: [AshAgent.Resource]

    agent do
      client "anthropic:claude-3-5-sonnet"
      output nil
      prompt "Test"
    end
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
      resource MinimalAgent
      resource AgentWithArgs
      resource AgentWithHooks
      resource NilOutputAgent
    end
  end

  describe "call/2" do
    test "successfully calls agent and returns structured result" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Success!"})
      )

      assert {:ok, %TestOutput{result: "Success!"}} = Runtime.call(MinimalAgent, %{})
    end

    test "passes arguments to agent" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Processed!"})
      )

      assert {:ok, %TestOutput{result: "Processed!"}} =
               Runtime.call(AgentWithArgs, input: "test data")
    end

    test "returns error tuple on LLM failure" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.error_response(500, "Server error"))

      assert {:error, _error} = Runtime.call(MinimalAgent, %{})
    end

    test "executes hooks in correct order" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Hooked!"})
      )

      {:ok, _result} = Runtime.call(AgentWithHooks, %{})

      assert_received {:before_call, %{}}
      assert_received {:after_render, "Test with hooks"}
      assert_received {:after_call, %TestOutput{result: "Hooked!"}}
    end

    test "executes on_error hook when error occurs" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.error_response(500))

      {:error, _error} = Runtime.call(AgentWithHooks, %{})

      assert_received {:on_error, _error}
    end
  end

  describe "call!/2" do
    test "returns result directly on success" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Direct success!"})
      )

      assert %TestOutput{result: "Direct success!"} = Runtime.call!(MinimalAgent, %{})
    end

    test "raises exception on error" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.error_response(500))

      assert_raise AshAgent.Error, fn ->
        Runtime.call!(MinimalAgent, %{})
      end
    end
  end

  describe "stream/2" do
    test "successfully initiates stream" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Streamed!"})
      )

      assert {:ok, stream} = Runtime.stream(MinimalAgent, %{})
      assert is_function(stream) or is_struct(stream, Stream)
    end

    test "passes arguments to streaming agent" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Stream processed!"})
      )

      assert {:ok, stream} = Runtime.stream(AgentWithArgs, input: "stream data")
      assert is_function(stream) or is_struct(stream, Stream)
    end

    test "executes before and after_render hooks for streaming" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Stream hooked!"})
      )

      {:ok, _stream} = Runtime.stream(AgentWithHooks, %{})

      assert_received {:before_call, %{}}
      assert_received {:after_render, "Test with hooks"}
    end
  end

  describe "stream!/2" do
    test "returns stream directly on success" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Direct stream!"})
      )

      stream = Runtime.stream!(MinimalAgent, %{})
      assert is_function(stream) or is_struct(stream, Stream)
    end
  end

  describe "error handling" do
    test "returns schema error when output type is nil" do
      result = Runtime.call(NilOutputAgent, %{})

      assert {:error, %Error{type: :schema_error, message: message}} = result
      assert message =~ "No output type"
    end

    test "returns llm_error on API failures" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.error_response(500, "Server error"))

      result = Runtime.call(MinimalAgent, %{})

      assert {:error, _error} = result
    end

    test "returns llm_error on timeout" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.timeout_error())

      result = Runtime.call(MinimalAgent, %{})

      assert {:error, _error} = result
    end

    test "returns llm_error on connection refused" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.connection_refused())

      result = Runtime.call(MinimalAgent, %{})

      assert {:error, _error} = result
    end
  end

  describe "telemetry" do
    test "emits call span with usage metadata" do
      parent = self()
      handler_id = {:ash_agent_telemetry_call, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ash_agent, :call, :stop],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Success!"})
      )

      try do
        assert {:ok, _} = Runtime.call(MinimalAgent, %{})

        assert_receive {:telemetry_event, [:ash_agent, :call, :stop], _measurements, metadata}
        assert metadata.status == :ok
        input_tokens = metadata.usage[:input_tokens] || metadata.usage["input_tokens"]
        assert input_tokens == 10
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits stream span metadata" do
      parent = self()
      handler_id = {:ash_agent_telemetry_stream, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ash_agent, :stream, :stop],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Stream!"})
      )

      try do
        assert {:ok, stream} = Runtime.stream(MinimalAgent, %{})
        Enum.to_list(stream)

        assert_receive {:telemetry_event, [:ash_agent, :stream, :stop], _measurements, metadata}
        assert metadata.status == :ok
      after
        :telemetry.detach(handler_id)
      end
    end
  end
end
