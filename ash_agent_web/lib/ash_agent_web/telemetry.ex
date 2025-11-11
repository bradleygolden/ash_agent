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
      [:ash_agent, :token_limit_warning]
    ]

    :telemetry.attach_many(
      "ash-agent-web-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:ash_agent, :call, :start], measurements, metadata, _config) do
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
    duration = measurements.duration

    call_data = %{
      agent: metadata.agent,
      status: metadata.status,
      duration_ms: System.convert_time_unit(duration, :native, :millisecond),
      usage: metadata[:usage],
      completed_at: System.system_time(:millisecond)
    }

    update_metrics(metadata.agent, call_data)

    Phoenix.PubSub.broadcast(
      AshAgentWeb.PubSub,
      "agent:#{metadata.agent}",
      {:call_completed, call_data}
    )
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
end
