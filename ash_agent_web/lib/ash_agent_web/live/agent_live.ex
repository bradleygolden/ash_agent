defmodule AshAgentWeb.AgentLive do
  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    agent = params["agent"] && String.to_existing_atom(params["agent"])

    if connected?(socket) && agent do
      Phoenix.PubSub.subscribe(AshAgentWeb.PubSub, "agent:#{agent}")
    end

    metrics = if agent, do: AshAgentWeb.Telemetry.get_metrics(agent), else: %{}

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:metrics, metrics)
      |> assign(:current_calls, [])
      |> assign(:call_history, [])

    {:ok, socket}
  end

  @impl true
  def handle_info({:call_started, call_data}, socket) do
    {:noreply, update(socket, :current_calls, &[call_data | &1])}
  end

  @impl true
  def handle_info({:call_completed, call_data}, socket) do
    metrics = AshAgentWeb.Telemetry.get_metrics(socket.assigns.agent)

    socket =
      socket
      |> assign(:metrics, metrics)
      |> update(:call_history, &[call_data | Enum.take(&1, 49)])
      |> update(:current_calls, fn calls ->
        Enum.reject(calls, &(&1.agent == call_data.agent))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:call_failed, call_data}, socket) do
    socket =
      socket
      |> update(:call_history, &[call_data | Enum.take(&1, 49)])
      |> update(:current_calls, fn calls ->
        Enum.reject(calls, &(&1.agent == call_data.agent))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:token_warning, metadata}, socket) do
    {:noreply, put_flash(socket, :warning, "Token limit warning: #{inspect(metadata)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="agent-dashboard">
      <div class="header">
        <h1>AshAgent Monitor</h1>
        <%= if @agent do %>
          <h2><%= inspect(@agent) %></h2>
        <% else %>
          <p>Select an agent to monitor</p>
        <% end %>
      </div>

      <%= if @agent do %>
        <div class="metrics-grid">
          <div class="metric-card">
            <div class="metric-label">Total Calls</div>
            <div class="metric-value"><%= @metrics[:total_calls] || 0 %></div>
          </div>

          <div class="metric-card">
            <div class="metric-label">Total Tokens</div>
            <div class="metric-value"><%= format_number(@metrics[:total_tokens] || 0) %></div>
          </div>

          <div class="metric-card">
            <div class="metric-label">Estimated Cost</div>
            <div class="metric-value">$<%= :erlang.float_to_binary(@metrics[:total_cost] || 0.0, decimals: 4) %></div>
          </div>

          <div class="metric-card">
            <div class="metric-label">Errors</div>
            <div class="metric-value error"><%= @metrics[:errors] || 0 %></div>
          </div>
        </div>

        <%= if length(@current_calls) > 0 do %>
          <div class="section">
            <h3>Active Calls (<%= length(@current_calls) %>)</h3>
            <div class="calls-list">
              <%= for call <- @current_calls do %>
                <div class="call-item active">
                  <span class="status-indicator running"></span>
                  <div class="call-info">
                    <div class="call-agent"><%= inspect(call.agent) %></div>
                    <div class="call-time">Started <%= relative_time(call.started_at) %></div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if length(@call_history) > 0 do %>
          <div class="section">
            <h3>Recent Calls</h3>
            <div class="calls-list">
              <%= for call <- @call_history do %>
                <div class="call-item">
                  <span class={"status-indicator #{call.status}"}></span>
                  <div class="call-info">
                    <div class="call-details">
                      <span class="call-status"><%= call.status %></span>
                      <span class="call-duration"><%= call.duration_ms %>ms</span>
                      <%= if call[:usage] do %>
                        <span class="call-tokens">
                          <%= get_total_tokens(call.usage) %> tokens
                        </span>
                      <% end %>
                    </div>
                    <div class="call-time">
                      <%= format_timestamp(call.completed_at) %>
                    </div>
                    <%= if call[:error] do %>
                      <div class="call-error"><%= call.error %></div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>

      <style>
        .agent-dashboard { padding: 2rem; font-family: system-ui, -apple-system, sans-serif; }
        .header { margin-bottom: 2rem; }
        .header h1 { margin: 0; font-size: 2rem; color: #1a1a1a; }
        .header h2 { margin: 0.5rem 0 0; font-size: 1.25rem; color: #666; font-weight: 500; }

        .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
        .metric-card { background: white; border: 1px solid #e5e5e5; border-radius: 8px; padding: 1.5rem; }
        .metric-label { font-size: 0.875rem; color: #666; margin-bottom: 0.5rem; text-transform: uppercase; letter-spacing: 0.5px; }
        .metric-value { font-size: 2rem; font-weight: 600; color: #1a1a1a; }
        .metric-value.error { color: #dc2626; }

        .section { margin-bottom: 2rem; }
        .section h3 { margin: 0 0 1rem; font-size: 1.25rem; color: #1a1a1a; }

        .calls-list { display: flex; flex-direction: column; gap: 0.5rem; }
        .call-item { background: white; border: 1px solid #e5e5e5; border-radius: 6px; padding: 1rem; display: flex; align-items: flex-start; gap: 1rem; }
        .call-item.active { border-color: #3b82f6; background: #eff6ff; }

        .status-indicator { width: 12px; height: 12px; border-radius: 50%; flex-shrink: 0; margin-top: 4px; }
        .status-indicator.running { background: #3b82f6; animation: pulse 2s infinite; }
        .status-indicator.ok { background: #10b981; }
        .status-indicator.error { background: #dc2626; }

        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }

        .call-info { flex: 1; min-width: 0; }
        .call-agent { font-weight: 600; color: #1a1a1a; }
        .call-details { display: flex; gap: 1rem; margin-bottom: 0.25rem; flex-wrap: wrap; }
        .call-status { text-transform: uppercase; font-size: 0.75rem; font-weight: 600; color: #666; }
        .call-duration, .call-tokens { font-size: 0.875rem; color: #666; }
        .call-time { font-size: 0.875rem; color: #999; }
        .call-error { margin-top: 0.5rem; padding: 0.5rem; background: #fee; border-radius: 4px; font-size: 0.875rem; color: #dc2626; font-family: monospace; }
      </style>
    </div>
    """
  end

  defp format_number(num) when num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 2)}M"
  end

  defp format_number(num) when num >= 1_000 do
    "#{Float.round(num / 1_000, 1)}K"
  end

  defp format_number(num), do: to_string(num)

  defp get_total_tokens(nil), do: 0

  defp get_total_tokens(usage) do
    Map.get(usage, :total_tokens) ||
      (Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0))
  end

  defp format_timestamp(ts) when is_integer(ts) do
    DateTime.from_unix!(ts, :millisecond)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_timestamp(_), do: "Unknown"

  defp relative_time(monotonic_time) do
    elapsed_ms = System.convert_time_unit(
      System.monotonic_time() - monotonic_time,
      :native,
      :millisecond
    )

    cond do
      elapsed_ms < 1000 -> "just now"
      elapsed_ms < 60_000 -> "#{div(elapsed_ms, 1000)}s ago"
      true -> "#{div(elapsed_ms, 60_000)}m ago"
    end
  end
end
