defmodule AshAgent.TelemetryTest do
  use ExUnit.Case, async: true

  alias AshAgent.Telemetry

  describe "span/3 for :call event" do
    setup do
      test_pid = self()
      ref = make_ref()

      handler_id = "test-handler-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        [
          [:ash_agent, :call, :start],
          [:ash_agent, :call, :stop],
          [:ash_agent, :call, :summary]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "emits :start event with system_time" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      Telemetry.span(:call, metadata, fn -> {:ok, %{}} end)

      assert_receive {:telemetry_event, [:ash_agent, :call, :start], measurements, _metadata}
      assert is_integer(measurements.system_time)
    end

    test "emits :stop event with duration" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      Telemetry.span(:call, metadata, fn -> {:ok, %{}} end)

      assert_receive {:telemetry_event, [:ash_agent, :call, :stop], measurements, _metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration > 0
    end

    test "emits :summary event" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      Telemetry.span(:call, metadata, fn -> {:ok, %{}} end)

      assert_receive {:telemetry_event, [:ash_agent, :call, :summary], measurements, _metadata}
      assert is_integer(measurements.duration)
    end

    test "metadata includes agent info in stop event when using enriched metadata" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test-client"}

      # To preserve metadata in stop event, return {result, metadata} tuple
      Telemetry.span(:call, metadata, fn ->
        {{:ok, %{data: "response"}}, %{agent: TestAgent, provider: :mock, client: "test-client"}}
      end)

      assert_receive {:telemetry_event, [:ash_agent, :call, :stop], _measurements,
                      %{agent: TestAgent} = stop_metadata}

      assert stop_metadata.provider == :mock
      assert stop_metadata.client == "test-client"
    end

    test "stop metadata includes :ok status on success" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      # Return {:ok, response} as first element of tuple, enriched metadata as second
      Telemetry.span(:call, metadata, fn ->
        {{:ok, %{result: "success"}}, metadata}
      end)

      assert_receive {:telemetry_event, [:ash_agent, :call, :stop], _measurements,
                      %{agent: TestAgent} = stop_metadata}

      assert stop_metadata.status == :ok
    end

    test "stop metadata includes :error status on failure" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      Telemetry.span(:call, metadata, fn ->
        {{:error, "something failed"}, metadata}
      end)

      assert_receive {:telemetry_event, [:ash_agent, :call, :stop], _measurements,
                      %{agent: TestAgent} = stop_metadata}

      assert stop_metadata.status == :error
      assert stop_metadata.error == "something failed"
    end

    test "returns the result and stop metadata" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      {result, returned_meta} =
        Telemetry.span(:call, metadata, fn ->
          {{:ok, %{data: 123}}, metadata}
        end)

      assert result == {:ok, %{data: 123}}
      assert returned_meta.status == :ok
    end

    test "handles non-tuple return (bare result)" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      # When returning just a result without enriched metadata, the result
      # might be interpreted differently based on its shape
      {result, returned_meta} = Telemetry.span(:call, metadata, fn -> "plain result" end)

      assert result == "plain result"
      # The metadata is the original since no enriched metadata was provided
      assert returned_meta.agent == TestAgent
    end

    test "supports enriched metadata from function" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      {result, returned_meta} =
        Telemetry.span(:call, metadata, fn ->
          {{:ok, %{data: "result"}}, %{agent: TestAgent, provider: :mock, extra: "value"}}
        end)

      assert result == {:ok, %{data: "result"}}
      assert returned_meta.extra == "value"
      assert returned_meta.status == :ok
    end
  end

  describe "span/3 for :stream event" do
    setup do
      test_pid = self()
      ref = make_ref()

      handler_id = "test-handler-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        [
          [:ash_agent, :stream, :start],
          [:ash_agent, :stream, :stop],
          [:ash_agent, :stream, :summary]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "emits :start event" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      Telemetry.span(:stream, metadata, fn ->
        {{:ok, []}, metadata}
      end)

      assert_receive {:telemetry_event, [:ash_agent, :stream, :start], _measurements, _metadata}
    end

    test "emits :stop event" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      Telemetry.span(:stream, metadata, fn ->
        {{:ok, []}, metadata}
      end)

      assert_receive {:telemetry_event, [:ash_agent, :stream, :stop], _measurements, _metadata}
    end

    test "emits :summary event" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      Telemetry.span(:stream, metadata, fn ->
        {{:ok, []}, metadata}
      end)

      assert_receive {:telemetry_event, [:ash_agent, :stream, :summary], _measurements, _metadata}
    end

    test "summary includes :kind as :stream" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      Telemetry.span(:stream, metadata, fn ->
        {{:ok, []}, metadata}
      end)

      assert_receive {:telemetry_event, [:ash_agent, :stream, :summary], _measurements,
                      summary_meta}

      assert summary_meta.kind == :stream
    end
  end

  describe "span/3 edge cases" do
    setup do
      test_pid = self()
      ref = make_ref()

      handler_id = "test-handler-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        [
          [:ash_agent, :call, :start],
          [:ash_agent, :call, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, handler_id: handler_id}
    end

    test "handles unknown result format" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      {result, returned_meta} = Telemetry.span(:call, metadata, fn -> "unknown format" end)

      assert result == "unknown format"
      assert returned_meta.status == :unknown
    end

    test "duration is measured as non-negative integer" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test"}

      Telemetry.span(:call, metadata, fn ->
        {{:ok, %{}}, metadata}
      end)

      assert_receive {:telemetry_event, [:ash_agent, :call, :stop], measurements, _metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
    end

    test "start metadata matches provided metadata" do
      metadata = %{agent: TestAgent, provider: :mock, client: "test", custom: "field"}

      Telemetry.span(:call, metadata, fn ->
        {{:ok, %{}}, metadata}
      end)

      assert_receive {:telemetry_event, [:ash_agent, :call, :start], _measurements, start_meta}
      assert start_meta.agent == TestAgent
      assert start_meta.provider == :mock
      assert start_meta.client == "test"
      assert start_meta.custom == "field"
    end
  end
end
