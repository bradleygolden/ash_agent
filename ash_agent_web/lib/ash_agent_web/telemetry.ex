defmodule AshAgentWeb.Telemetry do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    attach_telemetry_handlers()
    {:ok, %{}}
  end

  defp attach_telemetry_handlers do
    events = [
      [:ash_agent, :call, :start],
      [:ash_agent, :call, :stop],
      [:ash_agent, :call, :exception],
      [:ash_agent, :token_limit_warning],
      [:ash_agent, :iteration, :start],
      [:ash_agent, :tool_call, :start],
      [:ash_agent, :tool_call, :complete]
    ]

    :telemetry.attach_many(
      "ash-agent-web-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:ash_agent, :call, :start], _measurements, metadata, _config) do
    call_id = make_ref() |> :erlang.ref_to_list() |> to_string()

    call_data = %{
      id: call_id,
      agent: metadata.agent,
      started_at: System.monotonic_time(),
      status: :running,
      iterations: [],
      total_tokens: 0,
      error: nil
    }

    :ets.insert(:ash_agent_calls, {call_id, call_data})

    Phoenix.PubSub.broadcast(
      AshAgentWeb.PubSub,
      "agent:#{metadata.agent}",
      {:call_started, call_data}
    )
  end

  def handle_event([:ash_agent, :call, :stop], measurements, metadata, _config) do
    require Logger

    try do
      duration = measurements.duration

      Logger.debug("Telemetry :stop event metadata: #{inspect(Map.keys(metadata))}")
      Logger.debug("  :input present? #{Map.has_key?(metadata, :input)}")
      Logger.debug("  :result present? #{Map.has_key?(metadata, :result)}")
      Logger.debug("  :context present? #{Map.has_key?(metadata, :context)}")

      # Serialize context for UI display
      context_value = metadata[:context]
      Logger.info("TELEMETRY: Context value type: #{if is_nil(context_value), do: "nil", else: inspect(context_value.__struct__)}")
      context_data = serialize_context(context_value)
      Logger.info("TELEMETRY: Context serialized successfully")

      call_data = %{
        agent: metadata.agent,
        status: metadata.status,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond),
        usage: metadata[:usage],
        completed_at: System.system_time(:millisecond),
        # Capture additional metadata for UI display
        input: metadata[:input],
        result: metadata[:result],
        provider: metadata[:provider],
        client: metadata[:client],
        context: context_data,
        show_details: false,
        show_iterations: false
      }

      update_metrics(metadata.agent, call_data)

      Phoenix.PubSub.broadcast(
        AshAgentWeb.PubSub,
        "agent:#{metadata.agent}",
        {:call_completed, call_data}
      )
    rescue
      error ->
        Logger.error("Error in telemetry :stop handler: #{inspect(error)}")
        Logger.error("Metadata: #{inspect(metadata, pretty: true, limit: :infinity)}")
        # Still broadcast something so the UI doesn't get stuck
        Phoenix.PubSub.broadcast(
          AshAgentWeb.PubSub,
          "agent:#{metadata[:agent] || :unknown}",
          {:call_failed, %{
            agent: metadata[:agent] || :unknown,
            status: :error,
            duration_ms: 0,
            error: inspect(error),
            completed_at: System.system_time(:millisecond)
          }}
        )
    end
  end

  def handle_event([:ash_agent, :call, :exception], measurements, metadata, _config) do
    duration = measurements.duration

    call_data = %{
      agent: metadata.agent,
      status: :error,
      duration_ms: System.convert_time_unit(duration, :native, :millisecond),
      error: inspect(metadata.error),
      completed_at: System.system_time(:millisecond)
    }

    Phoenix.PubSub.broadcast(
      AshAgentWeb.PubSub,
      "agent:#{metadata.agent}",
      {:call_failed, call_data}
    )
  end

  def handle_event([:ash_agent, :token_limit_warning], _measurements, metadata, _config) do
    Phoenix.PubSub.broadcast(
      AshAgentWeb.PubSub,
      "agent:#{metadata.agent}",
      {:token_warning, metadata}
    )
  end

  def handle_event([:ash_agent, :iteration, :start], _measurements, metadata, _config) do
    require Logger
    Logger.info("TELEMETRY: Broadcasting iteration_started for agent #{inspect(metadata.agent)}, iteration #{metadata.iteration}")

    Phoenix.PubSub.broadcast(
      AshAgentWeb.PubSub,
      "agent:#{metadata.agent}",
      {:iteration_started, %{
        agent: metadata.agent,
        iteration: metadata.iteration,
        timestamp: System.system_time(:millisecond)
      }}
    )
  end

  def handle_event([:ash_agent, :tool_call, :start], _measurements, metadata, _config) do
    Phoenix.PubSub.broadcast(
      AshAgentWeb.PubSub,
      "agent:#{metadata.agent}",
      {:tool_call_started, %{
        agent: metadata.agent,
        iteration: metadata.iteration,
        tool_name: metadata.tool_name,
        tool_id: metadata.tool_id,
        arguments: metadata.arguments,
        timestamp: System.system_time(:millisecond)
      }}
    )
  end

  def handle_event([:ash_agent, :tool_call, :complete], _measurements, metadata, _config) do
    Phoenix.PubSub.broadcast(
      AshAgentWeb.PubSub,
      "agent:#{metadata.agent}",
      {:tool_call_completed, %{
        agent: metadata.agent,
        iteration: metadata.iteration,
        tool_name: metadata.tool_name,
        tool_id: metadata.tool_id,
        result: metadata[:result],
        error: metadata[:error],
        status: metadata.status,
        timestamp: System.system_time(:millisecond)
      }}
    )
  end

  defp update_metrics(agent, call_data) do
    metrics =
      case :ets.lookup(:ash_agent_metrics, agent) do
        [{^agent, existing}] -> existing
        [] -> %{total_calls: 0, total_tokens: 0, total_cost: 0.0, errors: 0}
      end

    updated =
      metrics
      |> Map.update(:total_calls, 1, &(&1 + 1))
      |> Map.update(:total_tokens, get_total_tokens(call_data[:usage]), fn current ->
        current + get_total_tokens(call_data[:usage])
      end)
      |> Map.update(:total_cost, estimate_cost(call_data[:usage]), fn current ->
        current + estimate_cost(call_data[:usage])
      end)
      |> maybe_increment_errors(call_data[:status])

    :ets.insert(:ash_agent_metrics, {agent, updated})
  end

  defp get_total_tokens(nil), do: 0

  defp get_total_tokens(usage) do
    Map.get(usage, :total_tokens) ||
      (Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0))
  end

  defp estimate_cost(nil), do: 0.0

  defp estimate_cost(usage) do
    input_tokens = Map.get(usage, :input_tokens, 0)
    output_tokens = Map.get(usage, :output_tokens, 0)

    input_cost_per_mtok = 3.0
    output_cost_per_mtok = 15.0

    (input_tokens / 1_000_000 * input_cost_per_mtok) +
      (output_tokens / 1_000_000 * output_cost_per_mtok)
  end

  defp maybe_increment_errors(metrics, :error) do
    Map.update(metrics, :errors, 1, &(&1 + 1))
  end

  defp maybe_increment_errors(metrics, _), do: metrics

  def get_metrics(agent) do
    case :ets.lookup(:ash_agent_metrics, agent) do
      [{^agent, metrics}] -> metrics
      [] -> %{total_calls: 0, total_tokens: 0, total_cost: 0.0, errors: 0}
    end
  end

  defp serialize_context(nil) do
    require Logger
    Logger.info("SERIALIZE: called with nil")
    nil
  end

  defp serialize_context(%AshAgent.Context{} = context) do
    require Logger
    Logger.info("SERIALIZE: AshAgent.Context with #{length(context.iterations)} iterations")

    Enum.each(context.iterations, fn iter ->
      Logger.info("SERIALIZE:   Iteration #{iter.number}: #{length(iter.messages)} messages, #{length(iter.tool_calls)} tool_calls")
    end)

    %{
      iterations: serialize_iterations(context.iterations),
      current_iteration: context.current_iteration,
      total_iterations: length(context.iterations),
      cumulative_tokens: AshAgent.Context.get_cumulative_tokens(context)
    }
  end

  defp serialize_context(other) do
    require Logger
    Logger.info("SERIALIZE: unexpected type: #{inspect(other.__struct__)}")
    nil
  end

  defp serialize_iterations(iterations) when is_list(iterations) do
    Enum.map(iterations, fn iteration ->
      %{
        number: iteration.number,
        messages: serialize_messages(iteration.messages),
        tool_calls: iteration.tool_calls || [],
        started_at: iteration.started_at,
        completed_at: iteration.completed_at,
        metadata: iteration.metadata || %{},
        show_details: false
      }
    end)
  end

  defp serialize_iterations(_), do: []

  defp serialize_messages(messages) when is_list(messages) do
    Enum.map(messages, fn message ->
      %{
        role: message.role,
        content: serialize_content(message.content),
        tool_calls: Map.get(message, :tool_calls)
      }
    end)
  end

  defp serialize_messages(_), do: []

  defp serialize_content(content) when is_binary(content), do: content
  defp serialize_content(content) when is_list(content), do: content
  defp serialize_content(content) when is_map(content), do: content
  defp serialize_content(_), do: ""
end
