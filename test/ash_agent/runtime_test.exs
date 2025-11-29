defmodule AshAgent.RuntimeTest do
  @moduledoc """
  Unit tests for AshAgent.Runtime module.

  Tests runtime execution without integration testing - focuses on internal logic.
  """
  use ExUnit.Case, async: true

  alias AshAgent.Error
  alias AshAgent.Runtime
  alias AshAgent.Test.LLMStub

  defmodule NoStreamProvider do
    @behaviour AshAgent.Provider

    def call(_client, _prompt, _schema, _opts, _context, _tools, _messages) do
      {:ok, %{result: "override"}}
    end

    def stream(_client, _prompt, _schema, _opts, _context, _tools, _messages) do
      {:error, :no_stream}
    end

    def introspect do
      %{provider: :no_stream, features: [:sync_call]}
    end
  end

  defmodule NoFunctionProvider do
    @behaviour AshAgent.Provider

    def call(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      if Keyword.has_key?(opts, :function) do
        {:error, :unexpected_function_opt}
      else
        {:ok, %{result: "ok"}}
      end
    end

    def stream(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      if Keyword.has_key?(opts, :function) do
        {:error, :unexpected_function_opt}
      else
        {:error, :no_stream}
      end
    end

    def introspect do
      %{provider: :no_function, features: [:sync_call]}
    end
  end

  defmodule MinimalAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
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

  defmodule AgentWithArgs do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
      prompt "Process: {{ input }}"
    end
  end

  defmodule AgentWithHooks do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

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
      output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
      prompt "Test with hooks"
      hooks(TestHooks)
    end
  end

  defmodule AgentWithClientOpts do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client(:mock_client, function: :streaming_chat_agent)
      output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
      prompt "Uses provider-specific client opts"
    end
  end

  defmodule StreamTelemetryAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :mock

      client [
        :mock,
        mock_chunks: [
          %{result: "chunk", usage: %{input_tokens: 1, output_tokens: 2, total_tokens: 3}},
          %{result: "done", usage: %{input_tokens: 4, output_tokens: 6, total_tokens: 10}}
        ]
      ]

      output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
      prompt "Stream telemetry"
    end
  end

  defmodule NilOutputAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.RuntimeTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      output_schema(nil)
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
      resource StreamTelemetryAgent
      resource NilOutputAgent
    end
  end

  describe "call/2" do
    test "successfully calls agent and returns structured result" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Success!"})
      )

      assert {:ok, %AshAgent.Result{output: output}} = Runtime.call(MinimalAgent, %{})
      assert output.result == "Success!"
    end

    test "passes arguments to agent" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{"result" => "Processed!"})
      )

      assert {:ok, %AshAgent.Result{output: output}} =
               Runtime.call(AgentWithArgs, input: "test data")

      assert output.result == "Processed!"
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
      assert_received {:after_call, %AshAgent.Result{output: output}}
      assert output.result == "Hooked!"
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

      assert %AshAgent.Result{output: output} = Runtime.call!(MinimalAgent, %{})
      assert output.result == "Direct success!"
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

    test "emits stream summary telemetry with usage and result metadata" do
      parent = self()
      handler_id = {:runtime_stream_summary, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ash_agent, :stream, :summary],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:stream_summary, metadata})
        end,
        nil
      )

      chunk_handler_id = {:runtime_stream_chunk, make_ref()}

      :telemetry.attach(
        chunk_handler_id,
        [:ash_agent, :stream, :chunk],
        fn _event, measurements, metadata, _ ->
          send(parent, {:stream_chunk, measurements, metadata})
        end,
        nil
      )

      try do
        assert {:ok, stream} = Runtime.stream(StreamTelemetryAgent, %{})
        _ = Enum.to_list(stream)

        assert_receive {:stream_summary, metadata}, 1_000
        assert metadata.status == :ok
        assert metadata.result.__struct__ == AshAgent.Result
        assert Map.get(metadata, :usage) == nil
        assert_receive {:stream_chunk, %{index: 0}, _}, 1_000
        assert_receive {:stream_chunk, %{index: 1}, _}, 1_000
        assert_receive {:stream_chunk, %{index: 2}, _}, 1_000
      after
        :telemetry.detach(handler_id)
        :telemetry.detach(chunk_handler_id)
      end
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

      _results = Enum.to_list(stream)
    end
  end

  describe "runtime overrides" do
    test "allows overriding provider and client per call" do
      assert {:ok, %AshAgent.Result{output: output}} =
               Runtime.call(MinimalAgent, %{}, provider: NoStreamProvider, client: :custom)

      assert output.result == "override"
    end

    test "rejects streaming when provider lacks streaming support" do
      assert {:error, %Error{type: :validation_error}} =
               Runtime.stream(MinimalAgent, %{}, provider: NoStreamProvider)
    end

    test "drops provider-specific client opts when provider changes" do
      assert {:ok, %AshAgent.Result{output: output}} =
               Runtime.call(AgentWithClientOpts, %{}, provider: NoFunctionProvider)

      assert output.result == "ok"
    end
  end

  describe "error handling" do
    test "returns schema error when output schema is nil" do
      result = Runtime.call(NilOutputAgent, %{})

      assert {:error, %Error{type: :schema_error, message: message}} = result
      assert message =~ "No output schema"
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
          if metadata.agent == MinimalAgent do
            send(parent, {:telemetry_event, event, measurements, metadata})
          end
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
