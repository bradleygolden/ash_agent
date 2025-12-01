defmodule AshAgent.Integration.ProviderMetadataTest do
  use ExUnit.Case, async: false

  alias AshAgent.{Metadata, Result}

  @moduletag :integration

  setup_all do
    ReqLLM.put_key(:openai_api_key, "ollama")
    :ok
  end

  setup do
    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  defmodule MetadataTestAgent do
    use Ash.Resource,
      domain: AshAgent.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client("openai:qwen3:1.7b",
        base_url: "http://localhost:11434/v1",
        api_key: "ollama",
        temperature: 0.0
      )

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))

      output_schema(
        Zoi.object(
          %{
            response: Zoi.string()
          },
          coerce: true
        )
      )

      instruction(~p"""
      Reply with JSON matching ctx.output_format exactly.
      response should echo the message.
      Message: {{ message }}
      {{ ctx.output_format }}
      """)
    end
  end

  describe "unified metadata extraction with ReqLLM/Ollama" do
    test "Result.metadata is populated with AshAgent.Metadata struct" do
      assert {:ok, %Result{metadata: metadata}} =
               AshAgent.Runtime.call(MetadataTestAgent, %{message: "metadata test"})

      assert %Metadata{} = metadata
    end

    test "metadata contains provider identifier" do
      assert {:ok, %Result{metadata: metadata}} =
               AshAgent.Runtime.call(MetadataTestAgent, %{message: "provider test"})

      assert metadata.provider == :req_llm
    end

    test "Result contains usage statistics" do
      assert {:ok, %Result{usage: usage}} =
               AshAgent.Runtime.call(MetadataTestAgent, %{message: "usage test"})

      assert is_map(usage)
      assert Map.has_key?(usage, :input_tokens) or Map.has_key?(usage, "input_tokens")
      assert Map.has_key?(usage, :output_tokens) or Map.has_key?(usage, "output_tokens")
    end

    test "Result contains model identifier" do
      assert {:ok, %Result{model: model}} =
               AshAgent.Runtime.call(MetadataTestAgent, %{message: "model test"})

      assert is_binary(model)
    end

    test "Result contains finish_reason" do
      assert {:ok, %Result{finish_reason: finish_reason}} =
               AshAgent.Runtime.call(MetadataTestAgent, %{message: "finish test"})

      assert finish_reason in [:stop, :end_turn, :length, nil] or is_atom(finish_reason)
    end
  end

  describe "mock provider metadata" do
    defmodule MockMetadataAgent do
      use Ash.Resource,
        domain: AshAgent.TestDomain,
        extensions: [AshAgent.Resource]

      import AshAgent.Sigils

      resource do
        require_primary_key? false
      end

      agent do
        provider :mock

        client("mock:test",
          mock_response: %{
            content: "mock response",
            metadata: %{
              duration_ms: 42,
              request_id: "mock_req_123",
              tags: %{"test" => true}
            }
          }
        )

        input_schema(Zoi.object(%{input: Zoi.string()}, coerce: true))
        output_schema(Zoi.object(%{content: Zoi.string()}, coerce: true))
        instruction(~p"Mock instruction: {{ input }}")
      end
    end

    test "mock provider extracts configurable metadata" do
      assert {:ok, %Result{metadata: metadata}} =
               AshAgent.Runtime.call(MockMetadataAgent, %{input: "test"})

      assert %Metadata{} = metadata
      assert metadata.provider == :mock
    end
  end

  describe "telemetry integration" do
    test "telemetry events include provider metadata" do
      test_pid = self()
      ref = make_ref()

      handler_id = "test-metadata-handler-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:ash_agent, :call, :stop],
        fn _event, _measurements, telemetry_metadata, _ ->
          send(test_pid, {:telemetry_stop, ref, telemetry_metadata})
        end,
        nil
      )

      try do
        {:ok, _result} =
          AshAgent.Runtime.call(MetadataTestAgent, %{message: "telemetry test"})

        assert_receive {:telemetry_stop, ^ref, telemetry_metadata}, 30_000

        assert telemetry_metadata[:status] == :ok
        assert is_map(telemetry_metadata[:usage]) or is_nil(telemetry_metadata[:usage])
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  describe "metadata serializability for persistence" do
    test "Result.metadata is JSON-encodable" do
      {:ok, result} = AshAgent.Runtime.call(MetadataTestAgent, %{message: "serialize test"})

      assert {:ok, json} = Jason.encode(result.metadata)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["provider"] == "req_llm"
    end

    test "Result.usage is JSON-encodable" do
      {:ok, result} = AshAgent.Runtime.call(MetadataTestAgent, %{message: "usage serialize"})

      assert {:ok, json} = Jason.encode(result.usage)
      assert {:ok, decoded} = Jason.decode(json)
      assert is_integer(decoded["input_tokens"])
    end

    test "full Result can be serialized for state capture" do
      {:ok, result} = AshAgent.Runtime.call(MetadataTestAgent, %{message: "state capture"})

      state = %{
        output: result.output,
        usage: result.usage,
        model: result.model,
        metadata: Map.from_struct(result.metadata),
        finish_reason: result.finish_reason
      }

      assert {:ok, _json} = Jason.encode(state)
    end
  end

  describe "context reconstruction for session continuity" do
    test "result.context can be used for next turn" do
      {:ok, result} = AshAgent.Runtime.call(MetadataTestAgent, %{message: "context test"})

      assert %AshAgent.Context{} = result.context
      assert length(result.context.messages) >= 2
    end

    test "context messages are serializable for persistence" do
      {:ok, result} = AshAgent.Runtime.call(MetadataTestAgent, %{message: "context serialize"})

      messages =
        Enum.map(result.context.messages, fn msg ->
          %{role: msg.role, content: msg.content}
        end)

      assert {:ok, _json} = Jason.encode(messages)
    end
  end

  describe "usage accumulation for budget tracking" do
    test "usage has required fields for accumulation" do
      {:ok, result} = AshAgent.Runtime.call(MetadataTestAgent, %{message: "budget test"})

      assert is_map(result.usage)

      assert Map.has_key?(result.usage, :input_tokens) or
               Map.has_key?(result.usage, "input_tokens")

      assert Map.has_key?(result.usage, :output_tokens) or
               Map.has_key?(result.usage, "output_tokens")
    end

    test "usage values are summable integers" do
      {:ok, result} = AshAgent.Runtime.call(MetadataTestAgent, %{message: "sum test"})

      input = result.usage[:input_tokens] || result.usage["input_tokens"]
      output = result.usage[:output_tokens] || result.usage["output_tokens"]

      assert is_integer(input) and input >= 0
      assert is_integer(output) and output >= 0

      total = input + output
      assert is_integer(total)
    end
  end

  describe "telemetry and result metadata consistency" do
    test "telemetry stop event contains same usage as Result" do
      test_pid = self()
      ref = make_ref()
      handler_id = "consistency-test-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:ash_agent, :call, :stop],
        fn _event, _measurements, telemetry_meta, _ ->
          send(test_pid, {:telemetry, ref, telemetry_meta})
        end,
        nil
      )

      try do
        {:ok, result} = AshAgent.Runtime.call(MetadataTestAgent, %{message: "consistency"})

        assert_receive {:telemetry, ^ref, telemetry_meta}, 30_000

        if result.usage do
          assert telemetry_meta[:usage] == result.usage
        end
      after
        :telemetry.detach(handler_id)
      end
    end

    test "telemetry contains status on success" do
      test_pid = self()
      ref = make_ref()
      handler_id = "status-test-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:ash_agent, :call, :stop],
        fn _event, _measurements, telemetry_meta, _ ->
          send(test_pid, {:telemetry, ref, telemetry_meta})
        end,
        nil
      )

      try do
        {:ok, _result} = AshAgent.Runtime.call(MetadataTestAgent, %{message: "status test"})

        assert_receive {:telemetry, ^ref, telemetry_meta}, 30_000

        assert telemetry_meta[:status] == :ok
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  describe "mock provider state capture" do
    alias AshAgent.Integration.ProviderMetadataTest.MockMetadataAgent

    test "mock provider returns configurable metadata for testing" do
      {:ok, result} = AshAgent.Runtime.call(MockMetadataAgent, %{input: "state capture"})

      assert %Metadata{} = result.metadata
      assert result.metadata.provider == :mock
    end

    test "mock provider metadata is serializable" do
      {:ok, result} = AshAgent.Runtime.call(MockMetadataAgent, %{input: "serialize mock"})

      state = Map.from_struct(result.metadata)
      assert {:ok, _json} = Jason.encode(state)
    end
  end
end
