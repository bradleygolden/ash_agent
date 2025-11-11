defmodule AshAgentWeb.AgentLive do
  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    agent = params["agent"] && String.to_existing_atom(params["agent"])

    if connected?(socket) && agent do
      Phoenix.PubSub.subscribe(AshAgentWeb.PubSub, "agent:#{agent}")
    end

    metrics = if agent, do: AshAgentWeb.Telemetry.get_metrics(agent), else: %{}
    agent_inputs = if agent, do: introspect_agent_inputs(agent), else: %{arguments: [], form_data: %{}}

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:metrics, metrics)
      |> assign(:current_calls, [])
      |> assign(:call_history, [])
      |> assign(:conversation_history, [])
      |> assign(:calling_agent, false)
      |> assign(:agent_inputs, agent_inputs)
      |> assign(:form_data, agent_inputs.form_data)

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
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> assign(:calling_agent, false)
      |> assign(:form_data, socket.assigns.agent_inputs.form_data)

    case result do
      {:ok, response, input_summary} ->
        conversation_entry = %{
          question: input_summary,
          response: response,
          timestamp: System.system_time(:millisecond),
          status: :success
        }

        {:noreply, update(socket, :conversation_history, &[conversation_entry | &1])}

      {:error, error, input_summary} ->
        conversation_entry = %{
          question: input_summary,
          response: nil,
          error: inspect(error),
          timestamp: System.system_time(:millisecond),
          status: :error
        }

        socket =
          socket
          |> update(:conversation_history, &[conversation_entry | &1])
          |> put_flash(:error, "Agent call failed: #{inspect(error)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    form_data = Map.put(socket.assigns.form_data, String.to_existing_atom(field), value)
    {:noreply, assign(socket, :form_data, form_data)}
  end

  @impl true
  def handle_event("call_agent", params, socket) do
    agent = socket.assigns.agent
    arguments = socket.assigns.agent_inputs.arguments

    input_map = build_input_map(params, arguments)

    if agent && valid_inputs?(input_map, arguments) do
      socket = assign(socket, :calling_agent, true)

      input_summary = format_input_summary(input_map, arguments)

      Task.async(fn ->
        try do
          result =
            agent
            |> Ash.ActionInput.for_action(:call, input_map)
            |> Ash.run_action!()

          {:ok, result, input_summary}
        rescue
          e -> {:error, e, input_summary}
        end
      end)

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Please fill in all required fields")}
    end
  end

  defp introspect_agent_inputs(agent) do
    case Ash.Resource.Info.action(agent, :call) do
      nil ->
        %{arguments: [], form_data: %{}}

      action ->
        arguments =
          action.arguments
          |> Enum.map(fn arg ->
            %{
              name: arg.name,
              type: arg.type,
              required: !arg.allow_nil?,
              default: arg.default,
              description: arg.description
            }
          end)

        form_data =
          arguments
          |> Enum.map(fn arg -> {arg.name, arg.default || ""} end)
          |> Map.new()

        %{arguments: arguments, form_data: form_data}
    end
  end

  defp build_input_map(params, arguments) do
    arguments
    |> Enum.map(fn arg ->
      value = params[to_string(arg.name)] || arg.default

      parsed_value =
        case arg.type do
          :integer -> parse_integer(value)
          :float -> parse_float(value)
          :boolean -> parse_boolean(value)
          _ -> value
        end

      {arg.name, parsed_value}
    end)
    |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
    |> Map.new()
  end

  defp valid_inputs?(input_map, arguments) do
    required_args = Enum.filter(arguments, & &1.required)

    Enum.all?(required_args, fn arg ->
      value = Map.get(input_map, arg.name)
      value != nil && value != ""
    end)
  end

  defp format_input_summary(input_map, arguments) do
    case arguments do
      [] ->
        "Agent called"

      [single] ->
        Map.get(input_map, single.name, "") |> to_string()

      multiple ->
        multiple
        |> Enum.map(fn arg ->
          value = Map.get(input_map, arg.name, "")
          "#{arg.name}: #{value}"
        end)
        |> Enum.join(", ")
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_integer(value), do: value

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp parse_float(value), do: value

  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(value) when is_boolean(value), do: value
  defp parse_boolean(_), do: nil

  defp humanize_field_name(atom) do
    atom
    |> to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp render_input_field(arg, value, disabled) do
    case arg.type do
      :string ->
        if String.contains?(to_string(arg.name), ["message", "question", "prompt", "text"]) do
          assigns = %{arg: arg, value: value, disabled: disabled}

          ~H"""
          <textarea
            name={to_string(@arg.name)}
            placeholder={"Enter #{humanize_field_name(@arg.name)}..."}
            rows="3"
            disabled={@disabled}
            class="question-input"
            required={@arg.required}
          ><%= @value %></textarea>
          """
        else
          assigns = %{arg: arg, value: value, disabled: disabled}

          ~H"""
          <input
            type="text"
            name={to_string(@arg.name)}
            value={@value}
            placeholder={"Enter #{humanize_field_name(@arg.name)}..."}
            disabled={@disabled}
            class="text-input"
            required={@arg.required}
          />
          """
        end

      :integer ->
        assigns = %{arg: arg, value: value, disabled: disabled}

        ~H"""
        <input
          type="number"
          name={to_string(@arg.name)}
          value={@value}
          placeholder={"Enter #{humanize_field_name(@arg.name)}..."}
          disabled={@disabled}
          class="text-input"
          required={@arg.required}
        />
        """

      :float ->
        assigns = %{arg: arg, value: value, disabled: disabled}

        ~H"""
        <input
          type="number"
          step="any"
          name={to_string(@arg.name)}
          value={@value}
          placeholder={"Enter #{humanize_field_name(@arg.name)}..."}
          disabled={@disabled}
          class="text-input"
          required={@arg.required}
        />
        """

      :boolean ->
        assigns = %{arg: arg, value: value, disabled: disabled}

        ~H"""
        <select name={to_string(@arg.name)} disabled={@disabled} class="select-input" required={@arg.required}>
          <option value="">Select...</option>
          <option value="true" selected={@value == true}>True</option>
          <option value="false" selected={@value == false}>False</option>
        </select>
        """

      _ ->
        assigns = %{arg: arg, value: value, disabled: disabled}

        ~H"""
        <input
          type="text"
          name={to_string(@arg.name)}
          value={to_string(@value)}
          placeholder={"Enter #{humanize_field_name(@arg.name)}..."}
          disabled={@disabled}
          class="text-input"
          required={@arg.required}
        />
        """
    end
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
        <div class="section interactive-section">
          <h3>Try the Agent</h3>
          <%= if length(@agent_inputs.arguments) == 0 do %>
            <form phx-submit="call_agent" class="agent-form">
              <p class="info-text">This agent takes no input arguments.</p>
              <button type="submit" disabled={@calling_agent} class="submit-button">
                <%= if @calling_agent do %>
                  <span class="spinner"></span> Calling agent...
                <% else %>
                  Call Agent
                <% end %>
              </button>
            </form>
          <% else %>
            <form phx-submit="call_agent" class="agent-form">
              <%= for arg <- @agent_inputs.arguments do %>
                <div class="form-group">
                  <label class="field-label">
                    <%= humanize_field_name(arg.name) %>
                    <%= if arg.required do %>
                      <span class="required-indicator">*</span>
                    <% end %>
                  </label>
                  <%= if arg.description do %>
                    <div class="field-description"><%= arg.description %></div>
                  <% end %>
                  <%= render_input_field(arg, @form_data[arg.name], @calling_agent) %>
                </div>
              <% end %>
              <button type="submit" disabled={@calling_agent} class="submit-button">
                <%= if @calling_agent do %>
                  <span class="spinner"></span> Calling agent...
                <% else %>
                  Send Request
                <% end %>
              </button>
            </form>
          <% end %>
        </div>

        <%= if length(@conversation_history) > 0 do %>
          <div class="section">
            <h3>Conversation History</h3>
            <div class="conversation-list">
              <%= for entry <- @conversation_history do %>
                <div class="conversation-entry">
                  <div class="conversation-question">
                    <div class="conversation-label">You asked:</div>
                    <div class="conversation-content"><%= entry.question %></div>
                    <div class="conversation-timestamp"><%= format_timestamp(entry.timestamp) %></div>
                  </div>
                  <%= if entry.status == :success do %>
                    <div class="conversation-response">
                      <div class="conversation-label">Agent responded:</div>
                      <div class="conversation-content"><%= format_response(entry.response) %></div>
                    </div>
                  <% else %>
                    <div class="conversation-error">
                      <div class="conversation-label">Error:</div>
                      <div class="conversation-content"><%= entry.error %></div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

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
        .agent-dashboard { padding: 2rem; font-family: system-ui, -apple-system, sans-serif; max-width: 1200px; margin: 0 auto; }
        .header { margin-bottom: 2rem; }
        .header h1 { margin: 0; font-size: 2rem; color: #1a1a1a; }
        .header h2 { margin: 0.5rem 0 0; font-size: 1.25rem; color: #666; font-weight: 500; }

        .interactive-section { background: white; border: 2px solid #3b82f6; border-radius: 8px; padding: 1.5rem; margin-bottom: 2rem; }
        .interactive-section h3 { margin: 0 0 1rem; color: #1a1a1a; }

        .agent-form { display: flex; flex-direction: column; gap: 1rem; }
        .form-group { display: flex; flex-direction: column; gap: 0.5rem; }

        .field-label {
          font-size: 0.875rem;
          font-weight: 600;
          color: #374151;
        }
        .required-indicator { color: #dc2626; margin-left: 0.25rem; }
        .field-description {
          font-size: 0.75rem;
          color: #6b7280;
          font-style: italic;
          margin-top: -0.25rem;
        }
        .info-text {
          color: #6b7280;
          font-size: 0.875rem;
          margin: 0 0 1rem 0;
        }

        .question-input, .text-input, .select-input {
          width: 100%;
          padding: 0.75rem;
          border: 1px solid #d1d5db;
          border-radius: 6px;
          font-size: 1rem;
          font-family: inherit;
        }
        .question-input { resize: vertical; }
        .question-input:focus, .text-input:focus, .select-input:focus {
          outline: none;
          border-color: #3b82f6;
          box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
        }
        .question-input:disabled, .text-input:disabled, .select-input:disabled {
          background: #f3f4f6;
          cursor: not-allowed;
        }

        .submit-button {
          align-self: flex-start;
          padding: 0.75rem 1.5rem;
          background: #3b82f6;
          color: white;
          border: none;
          border-radius: 6px;
          font-size: 1rem;
          font-weight: 600;
          cursor: pointer;
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .submit-button:hover:not(:disabled) { background: #2563eb; }
        .submit-button:disabled { background: #9ca3af; cursor: not-allowed; }

        .spinner {
          display: inline-block;
          width: 14px;
          height: 14px;
          border: 2px solid rgba(255,255,255,0.3);
          border-top-color: white;
          border-radius: 50%;
          animation: spin 0.6s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        .conversation-list { display: flex; flex-direction: column; gap: 1.5rem; }
        .conversation-entry { background: white; border: 1px solid #e5e5e5; border-radius: 8px; padding: 1.5rem; }
        .conversation-question { margin-bottom: 1rem; padding-bottom: 1rem; border-bottom: 1px solid #e5e5e5; }
        .conversation-response { }
        .conversation-error { background: #fee; padding: 1rem; border-radius: 6px; }
        .conversation-label { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; color: #666; margin-bottom: 0.5rem; letter-spacing: 0.5px; }
        .conversation-content { color: #1a1a1a; line-height: 1.6; white-space: pre-wrap; }
        .conversation-timestamp { font-size: 0.75rem; color: #999; margin-top: 0.5rem; }

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

  defp format_response(response) when is_binary(response), do: response

  defp format_response(response) when is_struct(response) do
    case Map.get(response, :result) || Map.get(response, :output) do
      nil -> inspect(response, pretty: true)
      value -> to_string(value)
    end
  end

  defp format_response(response), do: inspect(response, pretty: true)
end
