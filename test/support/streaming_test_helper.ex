defmodule AshAgent.Test.StreamingTestHelper do
  @moduledoc """
  Helper module for testing streaming functionality in AshAgent.

  Provides:
  - Configurable mock providers for streaming tests
  - Laziness verification helpers using counters
  - Common stream generators for testing edge cases
  - Telemetry assertion helpers for stream events

  ## Usage

      use AshAgent.Test.StreamingTestHelper

      test "stream is lazy" do
        counter = new_counter()
        stream = counted_stream(counter, 1..10, fn i -> %{content: "item_\#{i}"} end)

        assert_not_consumed(counter)

        Enum.take(stream, 3)

        assert_consumed_count(counter, 3)
      end

  ## Mock Providers

  The module provides `StreamingMockProvider` and `StreamErrorProvider` that can
  be used directly or configured via client options:

      agent do
        provider StreamingMockProvider
        client [:mock, mock_chunks: [%{content: "a"}, %{content: "b"}]]
      end

  """

  defmodule StreamingMockProvider do
    @moduledoc """
    Configurable mock provider for streaming tests.

    ## Options (via client_opts)

    - `:mock_response` - Response map for `call/7` (default: `%{content: "default"}`)
    - `:mock_chunks` - List of chunk maps for `stream/7` (default: 2 chunks)
    - `:mock_chunk_delay_ms` - Delay between chunks in milliseconds
    - `:mock_on_chunk` - Function called for each chunk `fn chunk -> chunk end`

    ## Examples

        # Basic usage
        agent do
          provider StreamingMockProvider
          client :mock
        end

        # Custom chunks with delay
        agent do
          provider StreamingMockProvider
          client [:mock, mock_chunks: [%{a: 1}, %{a: 2}], mock_chunk_delay_ms: 10]
        end

    """
    @behaviour AshAgent.Provider

    @impl true
    def call(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      response = Keyword.get(opts, :mock_response, %{content: "default"})
      {:ok, response}
    end

    @impl true
    def stream(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      chunks = Keyword.get(opts, :mock_chunks, default_chunks())
      delay = Keyword.get(opts, :mock_chunk_delay_ms)
      on_chunk = Keyword.get(opts, :mock_on_chunk, & &1)

      stream =
        Stream.map(chunks, fn chunk ->
          if delay, do: Process.sleep(delay)
          on_chunk.(chunk)
        end)

      {:ok, stream}
    end

    @impl true
    def introspect do
      %{
        provider: :streaming_mock,
        features: [:sync_call, :streaming, :tool_calling],
        models: ["mock:streaming"],
        constraints: %{max_tokens: :unlimited}
      }
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
    Mock provider that simulates various streaming error conditions.

    ## Options (via client_opts)

    - `:error_type` - Type of error to simulate:
      - `:immediate` - Error on stream initialization (default)
      - `:mid_stream` - Error after first chunk
      - `:empty` - Return empty stream
      - `:timeout` - Simulate timeout after delay

    ## Examples

        # Immediate error
        Runtime.stream(ErrorAgent, %{}, client_opts: [error_type: :immediate])

        # Mid-stream error
        Runtime.stream(ErrorAgent, %{}, client_opts: [error_type: :mid_stream])

    """
    @behaviour AshAgent.Provider

    @impl true
    def call(_client, _prompt, _schema, _opts, _context, _tools, _messages) do
      {:error, :not_implemented}
    end

    @impl true
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

        :timeout ->
          stream =
            Stream.resource(
              fn -> 0 end,
              fn _ ->
                Process.sleep(60_000)
                {[], 0}
              end,
              fn _ -> :ok end
            )

          {:ok, stream}
      end
    end

    @impl true
    def introspect do
      %{provider: :stream_error, features: [:streaming]}
    end
  end

  defmodule NoStreamProvider do
    @moduledoc """
    Mock provider that does not support streaming.

    Useful for testing provider capability validation.
    """
    @behaviour AshAgent.Provider

    @impl true
    def call(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      response = Keyword.get(opts, :mock_response, %{content: "sync only"})
      {:ok, response}
    end

    @impl true
    def stream(_client, _prompt, _schema, _opts, _context, _tools, _messages) do
      {:error, :streaming_not_supported}
    end

    @impl true
    def introspect do
      %{provider: :no_stream, features: [:sync_call]}
    end
  end

  @doc """
  Creates a new counter for tracking stream element consumption.

  Uses `:counters` module for atomic, concurrent-safe counting.

  ## Examples

      counter = new_counter()
      assert get_count(counter) == 0

  """
  def new_counter do
    :counters.new(1, [:atomics])
  end

  @doc """
  Gets the current count from a counter.

  ## Examples

      counter = new_counter()
      increment_counter(counter)
      assert get_count(counter) == 1

  """
  def get_count(counter) do
    :counters.get(counter, 1)
  end

  @doc """
  Increments a counter by 1.

  ## Examples

      counter = new_counter()
      increment_counter(counter)
      assert get_count(counter) == 1

  """
  def increment_counter(counter) do
    :counters.add(counter, 1, 1)
  end

  @doc """
  Creates a stream that increments a counter for each element consumed.

  Useful for verifying lazy evaluation of streams.

  ## Parameters

  - `counter` - Counter created with `new_counter/0`
  - `enumerable` - Source enumerable to map over
  - `transform_fn` - Optional function to transform each element

  ## Examples

      counter = new_counter()
      stream = counted_stream(counter, 1..10, fn i -> %{value: i} end)

      assert get_count(counter) == 0  # Not consumed yet

      Enum.take(stream, 3)

      assert get_count(counter) == 3  # Only 3 consumed

  """
  def counted_stream(counter, enumerable, transform_fn \\ & &1) do
    Stream.map(enumerable, fn item ->
      increment_counter(counter)
      transform_fn.(item)
    end)
  end

  @doc """
  Asserts that no elements have been consumed from a counted stream.

  ## Examples

      counter = new_counter()
      _stream = counted_stream(counter, 1..10)

      assert_not_consumed(counter)

  """
  defmacro assert_not_consumed(counter) do
    quote do
      assert :counters.get(unquote(counter), 1) == 0,
             "Expected stream to not be consumed, but #{:counters.get(unquote(counter), 1)} elements were consumed"
    end
  end

  @doc """
  Asserts that exactly `expected` elements have been consumed.

  ## Examples

      counter = new_counter()
      stream = counted_stream(counter, 1..10)

      Enum.take(stream, 5)

      assert_consumed_count(counter, 5)

  """
  defmacro assert_consumed_count(counter, expected) do
    quote do
      actual = :counters.get(unquote(counter), 1)

      assert actual == unquote(expected),
             "Expected #{unquote(expected)} elements consumed, but got #{actual}"
    end
  end

  @doc """
  Creates a stream of maps with incrementing content.

  ## Parameters

  - `count` - Number of elements to generate
  - `field` - Field name for the content (default: `:content`)
  - `prefix` - Prefix for content values (default: `"item_"`)

  ## Examples

      stream = content_stream(5)
      Enum.to_list(stream)
      #=> [%{content: "item_0"}, %{content: "item_1"}, ...]

      stream = content_stream(3, :message, "msg_")
      Enum.to_list(stream)
      #=> [%{message: "msg_0"}, %{message: "msg_1"}, %{message: "msg_2"}]

  """
  def content_stream(count, field \\ :content, prefix \\ "item_") do
    Stream.map(0..(count - 1), fn i ->
      %{field => "#{prefix}#{i}"}
    end)
  end

  @doc """
  Creates an infinite stream of maps.

  Must be used with `Enum.take/2` or similar to avoid infinite loops.

  ## Examples

      stream = infinite_content_stream()
      Enum.take(stream, 3)
      #=> [%{content: "item_0"}, %{content: "item_1"}, %{content: "item_2"}]

  """
  def infinite_content_stream(field \\ :content, prefix \\ "item_") do
    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn i -> %{field => "#{prefix}#{i}"} end)
  end

  @doc """
  Creates a stream with mixed valid and invalid chunks for error resilience testing.

  ## Examples

      stream = mixed_validity_stream()
      results = Enum.to_list(stream)
      # Contains: valid maps, nil, empty map, string

  """
  def mixed_validity_stream do
    Stream.map(
      [
        %{"content" => "valid1"},
        nil,
        %{"content" => "valid2"},
        %{},
        "string_chunk",
        %{"content" => "valid3"}
      ],
      & &1
    )
  end

  @doc """
  Sets up telemetry handler for capturing stream events.

  Returns a handler ID that must be detached in test cleanup.

  ## Parameters

  - `event_suffix` - The event suffix (`:start`, `:chunk`, `:stop`, `:summary`)
  - `pid` - Process to send captured events to (default: `self()`)

  ## Examples

      handler_id = attach_stream_telemetry(:chunk)

      try do
        {:ok, stream} = Runtime.stream(MyAgent, %{})
        Enum.to_list(stream)

        assert_receive {:stream_chunk, measurements, metadata}
      after
        detach_telemetry(handler_id)
      end

  """
  def attach_stream_telemetry(event_suffix, pid \\ self()) do
    handler_id = {__MODULE__, event_suffix, make_ref()}

    :telemetry.attach(
      handler_id,
      [:ash_agent, :stream, event_suffix],
      fn _event, measurements, metadata, _ ->
        send(pid, {:"stream_#{event_suffix}", measurements, metadata})
      end,
      nil
    )

    handler_id
  end

  @doc """
  Detaches a telemetry handler.

  ## Examples

      handler_id = attach_stream_telemetry(:start)
      # ... run test ...
      detach_telemetry(handler_id)

  """
  def detach_telemetry(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Runs a block with telemetry handlers attached, ensuring cleanup.

  ## Parameters

  - `events` - List of event suffixes to capture
  - `fun` - Function to run with handlers attached

  ## Examples

      with_stream_telemetry([:start, :chunk, :stop], fn ->
        {:ok, stream} = Runtime.stream(MyAgent, %{})
        Enum.to_list(stream)

        assert_receive {:stream_start, _, _}
        assert_receive {:stream_chunk, _, _}
        assert_receive {:stream_stop, _, _}
      end)

  """
  def with_stream_telemetry(events, fun) when is_list(events) and is_function(fun, 0) do
    handlers = Enum.map(events, &attach_stream_telemetry/1)

    try do
      fun.()
    after
      Enum.each(handlers, &detach_telemetry/1)
    end
  end

  defmacro __using__(_opts) do
    quote do
      import AshAgent.Test.StreamingTestHelper,
        only: [
          assert_not_consumed: 1,
          assert_consumed_count: 2
        ]

      alias AshAgent.Test.StreamingTestHelper
      alias AshAgent.Test.StreamingTestHelper.StreamingMockProvider
      alias AshAgent.Test.StreamingTestHelper.StreamErrorProvider
      alias AshAgent.Test.StreamingTestHelper.NoStreamProvider
    end
  end
end
