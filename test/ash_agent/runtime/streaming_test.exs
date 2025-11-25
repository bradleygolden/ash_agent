defmodule AshAgent.Runtime.StreamingTest do
  @moduledoc """
  Unit tests for streaming functionality in AshAgent.Runtime.

  These tests focus on streaming-specific behavior including:
  - Stream creation and consumption
  - Chunk handling and transformation
  - Early termination and cleanup
  - Error handling during streaming
  - Telemetry emission for stream lifecycle
  """
  use ExUnit.Case, async: true

  alias AshAgent.Runtime

  defmodule StreamOutput do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :content, :string, allow_nil?: false
      field :index, :integer
    end
  end

  defmodule StreamingMockProvider do
    @moduledoc """
    Mock provider that returns configurable stream responses for testing.
    """
    @behaviour AshAgent.Provider

    def call(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      response = Keyword.get(opts, :mock_response, %{content: "default"})
      {:ok, response}
    end

    def stream(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      chunks = Keyword.get(opts, :mock_chunks, default_chunks())

      stream =
        Stream.map(chunks, fn chunk ->
          if delay = Keyword.get(opts, :mock_chunk_delay_ms) do
            Process.sleep(delay)
          end

          chunk
        end)

      {:ok, stream}
    end

    def introspect do
      %{provider: :streaming_mock, features: [:sync_call, :streaming]}
    end

    defp default_chunks do
      [
        %{content: "Hello ", index: 0},
        %{content: "world!", index: 1}
      ]
    end
  end

  defmodule StreamErrorProvider do
    @moduledoc """
    Mock provider that returns errors during streaming for testing error handling.
    """
    @behaviour AshAgent.Provider

    def call(_client, _prompt, _schema, _opts, _context, _tools, _messages) do
      {:error, :not_implemented}
    end

    def stream(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      error_type = Keyword.get(opts, :error_type, :immediate)

      case error_type do
        :immediate ->
          {:error, "Stream initialization failed"}

        :mid_stream ->
          stream =
            Stream.resource(
              fn -> 0 end,
              fn
                0 -> {[%{content: "first"}], 1}
                1 -> raise "Mid-stream error"
              end,
              fn _ -> :ok end
            )

          {:ok, stream}

        :empty ->
          {:ok, Stream.map([], & &1)}
      end
    end

    def introspect do
      %{provider: :stream_error, features: [:streaming]}
    end
  end

  defmodule BasicStreamAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Runtime.StreamingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider StreamingMockProvider
      client :mock
      output StreamOutput
      prompt "Stream test"
    end
  end

  defmodule StreamAgentWithChunks do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Runtime.StreamingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :mock

      client [
        :mock,
        mock_chunks: [
          %{content: "chunk1", index: 0},
          %{content: "chunk2", index: 1},
          %{content: "chunk3", index: 2}
        ]
      ]

      output StreamOutput
      prompt "Multi-chunk stream"
    end
  end

  defmodule StreamAgentWithDelay do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Runtime.StreamingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :mock

      client [
        :mock,
        mock_chunks: [
          %{content: "slow1", index: 0},
          %{content: "slow2", index: 1}
        ],
        mock_chunk_delay_ms: 10
      ]

      output StreamOutput
      prompt "Delayed stream"
    end
  end

  defmodule StreamErrorAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Runtime.StreamingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider StreamErrorProvider
      client :mock
      output StreamOutput
      prompt "Error stream"
    end
  end

  defmodule EmptyStreamAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Runtime.StreamingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :mock
      client [:mock, mock_chunks: []]
      output StreamOutput
      prompt "Empty stream"
    end
  end

  defmodule SingleChunkAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Runtime.StreamingTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider :mock
      client [:mock, mock_chunks: [%{content: "only", index: 0}]]
      output StreamOutput
      prompt "Single chunk"
    end
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
      resource BasicStreamAgent
      resource StreamAgentWithChunks
      resource StreamAgentWithDelay
      resource StreamErrorAgent
      resource EmptyStreamAgent
      resource SingleChunkAgent
    end
  end

  describe "stream/2 basic functionality" do
    test "returns ok tuple with stream" do
      assert {:ok, stream} = Runtime.stream(BasicStreamAgent, %{})
      assert is_function(stream) or is_struct(stream, Stream)
    end

    test "stream yields chunks when consumed" do
      {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})

      results = Enum.to_list(stream)

      assert length(results) == 3
      assert Enum.at(results, 0).content == "chunk1"
      assert Enum.at(results, 1).content == "chunk2"
      assert Enum.at(results, 2).content == "chunk3"
    end

    test "stream converts chunks to output struct" do
      {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})

      results = Enum.to_list(stream)

      assert Enum.all?(results, &match?(%StreamOutput{}, &1))
    end

    test "handles single chunk stream" do
      {:ok, stream} = Runtime.stream(SingleChunkAgent, %{})

      results = Enum.to_list(stream)

      assert length(results) == 1
      assert %StreamOutput{content: "only", index: 0} = hd(results)
    end

    test "handles empty stream" do
      {:ok, stream} = Runtime.stream(EmptyStreamAgent, %{})

      results = Enum.to_list(stream)

      assert results == []
    end
  end

  describe "stream/2 with delays" do
    test "stream respects chunk delays" do
      start_time = System.monotonic_time(:millisecond)

      {:ok, stream} = Runtime.stream(StreamAgentWithDelay, %{})
      _results = Enum.to_list(stream)

      elapsed = System.monotonic_time(:millisecond) - start_time

      # 2 chunks * 10ms delay = 20ms minimum
      assert elapsed >= 20
    end
  end

  describe "stream/2 early termination" do
    test "stream supports Enum.take for partial consumption" do
      {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})

      results = Enum.take(stream, 2)

      assert length(results) == 2
      assert Enum.at(results, 0).content == "chunk1"
      assert Enum.at(results, 1).content == "chunk2"
    end

    test "stream supports Enum.take_while" do
      {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})

      results = Enum.take_while(stream, fn chunk -> chunk.index < 2 end)

      assert length(results) == 2
    end

    test "stream supports Stream.take" do
      {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})

      lazy_stream = Stream.take(stream, 1)
      results = Enum.to_list(lazy_stream)

      assert length(results) == 1
    end
  end

  describe "stream/2 error handling" do
    test "returns error when stream initialization fails" do
      result = Runtime.stream(StreamErrorAgent, %{})

      assert {:error, _error} = result
    end

    test "returns error when provider lacks streaming support" do
      defmodule NoStreamFeatureProvider do
        @behaviour AshAgent.Provider

        def call(_, _, _, _, _, _, _), do: {:ok, %{}}
        def stream(_, _, _, _, _, _, _), do: {:error, :not_supported}
        def introspect, do: %{provider: :no_stream, features: [:sync_call]}
      end

      result = Runtime.stream(BasicStreamAgent, %{}, provider: NoStreamFeatureProvider)

      assert {:error, error} = result
      assert error.type == :validation_error
    end
  end

  describe "stream!/2" do
    test "returns stream directly on success" do
      stream = Runtime.stream!(StreamAgentWithChunks, %{})

      assert is_function(stream) or is_struct(stream, Stream)
    end

    test "stream! result is consumable" do
      stream = Runtime.stream!(StreamAgentWithChunks, %{})

      results = Enum.to_list(stream)

      assert length(results) == 3
    end

    test "raises on error" do
      assert_raise AshAgent.Error, fn ->
        Runtime.stream!(StreamErrorAgent, %{})
      end
    end
  end

  describe "stream telemetry" do
    test "emits stream:start event when stream is created" do
      parent = self()
      handler_id = {:stream_start_test, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ash_agent, :stream, :start],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:stream_start, metadata})
        end,
        nil
      )

      try do
        {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})
        # Stream must be consumed to trigger telemetry
        _ = Enum.to_list(stream)

        assert_receive {:stream_start, metadata}, 1_000
        assert metadata.agent == StreamAgentWithChunks
        assert metadata.type == :stream
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits stream:chunk events for each chunk" do
      parent = self()
      handler_id = {:stream_chunk_test, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ash_agent, :stream, :chunk],
        fn _event, measurements, metadata, _ ->
          send(parent, {:stream_chunk, measurements, metadata})
        end,
        nil
      )

      try do
        {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})
        _ = Enum.to_list(stream)

        assert_receive {:stream_chunk, %{index: 0}, _}, 1_000
        assert_receive {:stream_chunk, %{index: 1}, _}, 1_000
        assert_receive {:stream_chunk, %{index: 2}, _}, 1_000
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits stream:stop event when stream completes" do
      parent = self()
      handler_id = {:stream_stop_test, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ash_agent, :stream, :stop],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:stream_stop, metadata})
        end,
        nil
      )

      try do
        {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})
        _ = Enum.to_list(stream)

        assert_receive {:stream_stop, metadata}, 1_000
        assert metadata.status == :ok
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits stream:summary event with final result" do
      parent = self()
      handler_id = {:stream_summary_test, make_ref()}

      :telemetry.attach(
        handler_id,
        [:ash_agent, :stream, :summary],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:stream_summary, metadata})
        end,
        nil
      )

      try do
        {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})
        _ = Enum.to_list(stream)

        assert_receive {:stream_summary, metadata}, 1_000
        assert metadata.status == :ok
        assert %StreamOutput{} = metadata.result
      after
        :telemetry.detach(handler_id)
      end
    end

    test "chunk index increments correctly" do
      handler_id = {:stream_index_test, make_ref()}
      indices = :ets.new(:indices, [:bag, :public])

      :telemetry.attach(
        handler_id,
        [:ash_agent, :stream, :chunk],
        fn _event, measurements, _metadata, _ ->
          :ets.insert(indices, {:index, measurements.index})
        end,
        nil
      )

      try do
        {:ok, stream} = Runtime.stream(StreamAgentWithChunks, %{})
        _ = Enum.to_list(stream)

        # Give telemetry events time to be processed
        Process.sleep(100)

        recorded_indices =
          :ets.lookup(indices, :index)
          |> Enum.map(fn {:index, i} -> i end)
          |> Enum.sort()

        assert recorded_indices == [0, 1, 2]
      after
        :telemetry.detach(handler_id)
        :ets.delete(indices)
      end
    end
  end

  describe "stream with runtime overrides" do
    test "allows overriding client options for streaming" do
      # BasicStreamAgent uses StreamingMockProvider which defaults to 2 chunks
      # Override with custom chunks via client_opts
      {:ok, stream} =
        Runtime.stream(BasicStreamAgent, %{},
          client_opts: [mock_chunks: [%{content: "override", index: 0}]]
        )

      results = Enum.to_list(stream)

      assert length(results) == 1
      assert hd(results).content == "override"
    end

    test "stream respects provider override" do
      # Use the mock provider which supports custom chunks
      # When overriding provider, must also pass client_opts for the new provider
      {:ok, stream} =
        Runtime.stream(BasicStreamAgent, %{},
          provider: :mock,
          client_opts: [mock_chunks: [%{content: "from_mock", index: 0}]]
        )

      results = Enum.to_list(stream)

      assert length(results) == 1
      assert hd(results).content == "from_mock"
    end
  end
end
