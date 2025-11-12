defmodule AshAgentWeb.AgentLiveTrace do
  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    agent = params["agent"] && String.to_existing_atom(params["agent"])

    if connected?(socket) && agent do
      Phoenix.PubSub.subscribe(AshAgentWeb.PubSub, "agent:#{agent}")
    end

    agent_inputs = if agent, do: introspect_agent_inputs(agent), else: %{arguments: [], form_data: %{}}
    agent_tools = if agent, do: introspect_agent_tools(agent), else: []

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:calling_agent, false)
      |> assign(:agent_inputs, agent_inputs)
      |> assign(:form_data, agent_inputs.form_data)
      |> assign(:agent_tools, agent_tools)
      |> assign(:trace_spans, [])
      |> assign(:selected_span, nil)
      |> assign(:expanded_spans, MapSet.new())

    {:ok, socket}
  end

  @impl true
  def handle_info({:call_started, _call_data}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:call_completed, call_data}, socket) do
    # Build trace from completed call
    if call_data[:context] && call_data.context[:iterations] do
      trace_spans = build_trace_spans(call_data)
      {:noreply, assign(socket, :trace_spans, trace_spans)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:call_failed, _call_data}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:token_warning, _metadata}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:iteration_started, _data}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:tool_call_started, _data}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:tool_call_completed, _data}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> assign(:calling_agent, false)
      |> assign(:form_data, socket.assigns.agent_inputs.form_data)

    case result do
      {:ok, _response, _input_data} ->
        {:noreply, socket}

      {:error, error, _input_data} ->
        socket =
          socket
          |> put_flash(:error, "Agent call failed: #{inspect(error)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("call_agent", params, socket) do
    agent = socket.assigns.agent
    arguments = socket.assigns.agent_inputs.arguments
    input_map = build_input_map(params, arguments)

    if agent && valid_inputs?(input_map, arguments) do
      socket = assign(socket, :calling_agent, true)

      Task.async(fn ->
        try do
          result =
            agent
            |> Ash.ActionInput.for_action(:call, input_map)
            |> Ash.run_action!()

          {:ok, result, input_map}
        rescue
          e -> {:error, e, input_map}
        end
      end)

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Please fill in all required fields")}
    end
  end

  @impl true
  def handle_event("toggle_span", %{"span_id" => span_id}, socket) do
    expanded = socket.assigns.expanded_spans

    updated_expanded =
      if MapSet.member?(expanded, span_id) do
        MapSet.delete(expanded, span_id)
      else
        MapSet.put(expanded, span_id)
      end

    {:noreply, assign(socket, :expanded_spans, updated_expanded)}
  end

  @impl true
  def handle_event("select_span", %{"span_id" => span_id}, socket) do
    selected_span = find_span_by_id(socket.assigns.trace_spans, span_id)
    {:noreply, assign(socket, :selected_span, selected_span)}
  end

  @impl true
  def handle_event("close_details", _params, socket) do
    {:noreply, assign(socket, :selected_span, nil)}
  end

  # Build hierarchical trace structure from call_data
  defp build_trace_spans(call_data) do
    start_time = call_data.completed_at - call_data.duration_ms

    root_span = %{
      id: "root",
      parent_id: nil,
      name: "Agent Execution",
      type: :agent,
      start_time: start_time,
      end_time: call_data.completed_at,
      duration_ms: call_data.duration_ms,
      status: call_data.status,
      metadata: %{
        agent: call_data.agent,
        total_tokens: call_data.context[:cumulative_tokens]
      },
      children: []
    }

    iterations = call_data.context[:iterations] || []

    children =
      Enum.map(iterations, fn iteration ->
        build_iteration_span(iteration, start_time)
      end)

    [Map.put(root_span, :children, children)]
  end

  defp build_iteration_span(iteration, agent_start_time) do
    # Use actual iteration timestamps
    iter_start = if iteration.started_at do
      DateTime.to_unix(iteration.started_at, :millisecond)
    else
      agent_start_time
    end

    iter_end = if iteration.completed_at do
      DateTime.to_unix(iteration.completed_at, :millisecond)
    else
      iter_start
    end

    duration = iter_end - iter_start

    span_id = "iteration-#{iteration.number}"

    # Build tool call spans with REAL timing data
    tool_spans =
      Enum.map(iteration.tool_calls || [], fn tool_call ->
        # Use actual timing data if available, otherwise estimate
        tool_start = if tool_call[:started_at] do
          DateTime.to_unix(tool_call.started_at, :millisecond)
        else
          iter_start
        end

        tool_end = if tool_call[:completed_at] do
          DateTime.to_unix(tool_call.completed_at, :millisecond)
        else
          tool_start
        end

        tool_duration = tool_call[:duration_ms] || (tool_end - tool_start)

        %{
          id: "tool-#{tool_call.id}",
          parent_id: span_id,
          name: "Tool: #{tool_call.name}",
          type: :tool,
          start_time: tool_start,
          end_time: tool_end,
          duration_ms: tool_duration,
          status: :success,
          metadata: %{
            tool_name: tool_call.name,
            arguments: tool_call.arguments
          },
          children: []
        }
      end)

    # Build LLM call span with REAL timing data
    llm_spans = build_llm_spans(iteration, iter_start, span_id)

    %{
      id: span_id,
      parent_id: "root",
      name: "Iteration #{iteration.number}",
      type: :iteration,
      start_time: iter_start,
      end_time: iter_end,
      duration_ms: duration,
      status: :success,
      metadata: %{
        iteration: iteration.number,
        message_count: length(iteration.messages || []),
        tool_call_count: length(iteration.tool_calls || []),
        tokens: iteration.metadata[:current_usage]
      },
      children: llm_spans ++ tool_spans
    }
  end

  defp build_llm_spans(iteration, iter_start, parent_id) do
    messages = iteration.messages || []
    metadata = iteration.metadata || %{}

    # Use actual LLM timing from metadata if available
    if length(messages) > 0 do
      llm_duration = metadata[:llm_duration_ms] || 0

      llm_end = if metadata[:llm_response_at] do
        DateTime.to_unix(metadata.llm_response_at, :millisecond)
      else
        iter_start + llm_duration
      end

      [
        %{
          id: "llm-#{parent_id}",
          parent_id: parent_id,
          name: "LLM Call",
          type: :llm,
          start_time: iter_start,
          end_time: llm_end,
          duration_ms: llm_duration,
          status: :success,
          metadata: %{
            message_count: length(messages),
            tokens: metadata[:current_usage]
          },
          children: []
        }
      ]
    else
      []
    end
  end

  defp find_span_by_id(spans, span_id) do
    Enum.find_value(spans, fn span ->
      cond do
        span.id == span_id -> span
        true -> find_span_by_id(span.children, span_id)
      end
    end)
  end

  # Helper functions
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

  defp introspect_agent_tools(agent) do
    AshAgent.Info.tools(agent)
    |> Enum.map(fn tool ->
      %{
        name: tool.name,
        description: tool.description,
        parameters: tool.parameters
      }
    end)
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

  defp format_duration(ms) when is_number(ms) do
    cond do
      ms < 1 -> "< 1ms"
      ms < 1000 -> "#{round(ms)}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 2)}s"
      true -> "#{div(ms, 60_000)}m #{rem(div(ms, 1000), 60)}s"
    end
  end
  defp format_duration(_), do: "?"

  defp status_color(status) do
    case status do
      :success -> "green"
      :ok -> "green"
      :error -> "red"
      :running -> "yellow"
      _ -> "gray"
    end
  end

  defp calculate_bar_style(span, all_spans) do
    # Find the root span to get total duration
    root = List.first(all_spans)
    total_duration = root.duration_ms

    # Calculate relative position and width
    relative_start = span.start_time - root.start_time
    width_percent = (span.duration_ms / total_duration) * 100
    left_percent = (relative_start / total_duration) * 100

    "width: #{width_percent}%; left: #{left_percent}%; background-color: #{get_span_color(span.type, span.status)}"
  end

  defp get_span_color(type, status) do
    case {type, status} do
      {:agent, :success} -> "#10b981"
      {:agent, :ok} -> "#10b981"
      {:agent, :error} -> "#ef4444"
      {:iteration, _} -> "#8b5cf6"
      {:llm, _} -> "#3b82f6"
      {:tool, _} -> "#f59e0b"
      _ -> "#6b7280"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="trace-container">
      <!-- Header -->
      <div class="trace-header">
        <div class="header-content">
          <a href="/" class="back-link">← All Agents</a>
          <h1 class="agent-title"><%= inspect(@agent) %></h1>
        </div>
      </div>

      <div class="trace-layout">
        <!-- Main Trace View -->
        <div class="trace-main">
          <!-- Input Form -->
          <div class="trace-input-panel">
            <h3>Test Agent</h3>
            <form phx-submit="call_agent" class="trace-form">
              <%= if length(@agent_inputs.arguments) == 0 do %>
                <div class="no-args-info">This agent takes no input arguments</div>
                <button type="submit" disabled={@calling_agent} class="submit-btn">
                  <%= if @calling_agent do %>
                    <span class="spinner"></span> Calling...
                  <% else %>
                    Call Agent
                  <% end %>
                </button>
              <% else %>
                <%= for arg <- @agent_inputs.arguments do %>
                  <div class="form-field">
                    <label>
                      <%= humanize_field_name(arg.name) %>
                      <%= if arg.required do %><span class="required">*</span><% end %>
                    </label>
                    <%= render_input_field(arg, @form_data[arg.name], @calling_agent) %>
                  </div>
                <% end %>
                <button type="submit" disabled={@calling_agent} class="submit-btn">
                  <%= if @calling_agent do %>
                    <span class="spinner"></span> Calling...
                  <% else %>
                    Run Trace
                  <% end %>
                </button>
              <% end %>
            </form>
          </div>

          <!-- Trace Waterfall -->
          <%= if length(@trace_spans) > 0 do %>
            <div class="trace-waterfall">
              <h3>Execution Trace</h3>
              <div class="waterfall-container">
                <div class="waterfall-header">
                  <div class="header-labels">Span</div>
                  <div class="header-timeline">Timeline</div>
                </div>

                <%= for span <- @trace_spans do %>
                  <%= render_span(assigns, span, 0) %>
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="trace-empty">
              <div class="empty-icon">📊</div>
              <p>Run the agent to see execution trace</p>
            </div>
          <% end %>
        </div>

        <!-- Details Panel -->
        <%= if @selected_span do %>
          <div class="trace-details-panel">
            <div class="details-header">
              <h3>Span Details</h3>
              <button phx-click="close_details" class="close-btn">✕</button>
            </div>
            <div class="details-content">
              <div class="detail-section">
                <div class="detail-label">Name</div>
                <div class="detail-value"><%= @selected_span.name %></div>
              </div>

              <div class="detail-section">
                <div class="detail-label">Type</div>
                <div class="detail-value"><%= @selected_span.type %></div>
              </div>

              <div class="detail-section">
                <div class="detail-label">Duration</div>
                <div class="detail-value"><%= format_duration(@selected_span.duration_ms) %></div>
              </div>

              <div class="detail-section">
                <div class="detail-label">Status</div>
                <div class={"detail-value status-#{@selected_span.status}"}>
                  <%= @selected_span.status %>
                </div>
              </div>

              <%= if @selected_span.metadata && map_size(@selected_span.metadata) > 0 do %>
                <div class="detail-section">
                  <div class="detail-label">Metadata</div>
                  <pre class="detail-code"><%= inspect(@selected_span.metadata, pretty: true) %></pre>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <style>
        .trace-container {
          display: flex;
          flex-direction: column;
          height: 100vh;
          background: #f5f5f5;
          font-family: system-ui, -apple-system, sans-serif;
        }

        .trace-header {
          background: white;
          border-bottom: 1px solid #e0e0e0;
          padding: 1rem 1.5rem;
          flex-shrink: 0;
        }

        .header-content {
          display: flex;
          align-items: center;
          gap: 1rem;
        }

        .back-link {
          color: #3b82f6;
          text-decoration: none;
          font-size: 0.875rem;
        }

        .agent-title {
          font-size: 1.25rem;
          font-weight: 600;
          color: #1a1a1a;
        }

        .view-badge {
          background: #eff6ff;
          color: #3b82f6;
          padding: 0.25rem 0.75rem;
          border-radius: 12px;
          font-size: 0.75rem;
          font-weight: 600;
        }

        .trace-layout {
          display: flex;
          flex: 1;
          overflow: hidden;
        }

        .trace-main {
          flex: 1;
          overflow-y: auto;
          padding: 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.5rem;
        }

        .trace-input-panel {
          background: white;
          border: 1px solid #e0e0e0;
          border-radius: 8px;
          padding: 1.5rem;
        }

        .trace-input-panel h3 {
          margin: 0 0 1rem;
          font-size: 1rem;
          font-weight: 600;
        }

        .trace-form {
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }

        .form-field {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }

        .form-field label {
          font-size: 0.875rem;
          font-weight: 600;
          color: #374151;
        }

        .required {
          color: #dc2626;
        }

        .form-field input,
        .form-field textarea,
        .form-field select {
          padding: 0.5rem;
          border: 1px solid #d1d5db;
          border-radius: 4px;
          font-size: 0.875rem;
        }

        .submit-btn {
          align-self: flex-start;
          padding: 0.5rem 1rem;
          background: #3b82f6;
          color: white;
          border: none;
          border-radius: 6px;
          font-size: 0.875rem;
          font-weight: 600;
          cursor: pointer;
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }

        .submit-btn:hover:not(:disabled) {
          background: #2563eb;
        }

        .submit-btn:disabled {
          background: #9ca3af;
          cursor: not-allowed;
        }

        .spinner {
          display: inline-block;
          width: 12px;
          height: 12px;
          border: 2px solid rgba(255,255,255,0.3);
          border-top-color: white;
          border-radius: 50%;
          animation: spin 0.6s linear infinite;
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }

        .trace-waterfall {
          background: white;
          border: 1px solid #e0e0e0;
          border-radius: 8px;
          padding: 1.5rem;
        }

        .trace-waterfall h3 {
          margin: 0 0 1rem;
          font-size: 1rem;
          font-weight: 600;
        }

        .waterfall-container {
          display: flex;
          flex-direction: column;
        }

        .waterfall-header {
          display: grid;
          grid-template-columns: 300px 1fr;
          gap: 1rem;
          padding-bottom: 0.5rem;
          border-bottom: 2px solid #e0e0e0;
          margin-bottom: 0.5rem;
          font-size: 0.75rem;
          font-weight: 600;
          text-transform: uppercase;
          color: #6b7280;
        }

        .span-row {
          display: grid;
          grid-template-columns: 300px 1fr;
          gap: 1rem;
          padding: 0.5rem 0;
          border-bottom: 1px solid #f3f4f6;
          cursor: pointer;
        }

        .span-row:hover {
          background: #f9fafb;
        }

        .span-label {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.875rem;
        }

        .expand-toggle {
          width: 16px;
          height: 16px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.75rem;
          cursor: pointer;
        }

        .span-name {
          font-weight: 500;
          color: #1f2937;
        }

        .span-duration {
          font-size: 0.75rem;
          color: #6b7280;
          margin-left: 0.5rem;
        }

        .span-timeline {
          position: relative;
          height: 24px;
          display: flex;
          align-items: center;
        }

        .timeline-bar {
          position: absolute;
          height: 16px;
          border-radius: 3px;
          opacity: 0.9;
          transition: opacity 0.2s;
        }

        .timeline-bar:hover {
          opacity: 1;
        }

        .trace-empty {
          background: white;
          border: 1px solid #e0e0e0;
          border-radius: 8px;
          padding: 3rem;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          color: #6b7280;
        }

        .empty-icon {
          font-size: 3rem;
          margin-bottom: 1rem;
        }

        .trace-details-panel {
          width: 400px;
          background: white;
          border-left: 1px solid #e0e0e0;
          display: flex;
          flex-direction: column;
          overflow-y: auto;
        }

        .details-header {
          padding: 1rem 1.5rem;
          border-bottom: 1px solid #e0e0e0;
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .details-header h3 {
          margin: 0;
          font-size: 1rem;
          font-weight: 600;
        }

        .close-btn {
          background: none;
          border: none;
          font-size: 1.25rem;
          cursor: pointer;
          color: #6b7280;
        }

        .details-content {
          padding: 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.5rem;
        }

        .detail-section {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }

        .detail-label {
          font-size: 0.75rem;
          font-weight: 600;
          text-transform: uppercase;
          color: #6b7280;
          letter-spacing: 0.5px;
        }

        .detail-value {
          color: #1f2937;
          font-size: 0.875rem;
        }

        .detail-code {
          background: #1f2937;
          color: #e5e7eb;
          padding: 0.75rem;
          border-radius: 4px;
          font-size: 0.75rem;
          overflow-x: auto;
          margin: 0;
        }

        .status-success, .status-ok {
          color: #10b981;
          font-weight: 600;
        }

        .status-error {
          color: #ef4444;
          font-weight: 600;
        }

        .status-running {
          color: #f59e0b;
          font-weight: 600;
        }
      </style>
    </div>
    """
  end

  defp render_input_field(arg, value, disabled) do
    case arg.type do
      :string ->
        if String.contains?(to_string(arg.name), ["message", "question", "prompt", "text"]) do
          assigns = %{arg: arg, value: value, disabled: disabled}
          ~H"""
          <textarea name={to_string(@arg.name)} disabled={@disabled} required={@arg.required}><%= @value %></textarea>
          """
        else
          assigns = %{arg: arg, value: value, disabled: disabled}
          ~H"""
          <input type="text" name={to_string(@arg.name)} value={@value} disabled={@disabled} required={@arg.required} />
          """
        end

      :integer ->
        assigns = %{arg: arg, value: value, disabled: disabled}
        ~H"""
        <input type="number" name={to_string(@arg.name)} value={@value} disabled={@disabled} required={@arg.required} />
        """

      :float ->
        assigns = %{arg: arg, value: value, disabled: disabled}
        ~H"""
        <input type="number" step="any" name={to_string(@arg.name)} value={@value} disabled={@disabled} required={@arg.required} />
        """

      :boolean ->
        assigns = %{arg: arg, value: value, disabled: disabled}
        ~H"""
        <select name={to_string(@arg.name)} disabled={@disabled} required={@arg.required}>
          <option value="">Select...</option>
          <option value="true" selected={@value == true}>True</option>
          <option value="false" selected={@value == false}>False</option>
        </select>
        """

      _ ->
        assigns = %{arg: arg, value: value, disabled: disabled}
        ~H"""
        <input type="text" name={to_string(@arg.name)} value={to_string(@value)} disabled={@disabled} required={@arg.required} />
        """
    end
  end

  defp render_span(assigns, span, depth) do
    is_expanded = MapSet.member?(assigns.expanded_spans, span.id)
    has_children = length(span.children) > 0
    indent_px = depth * 20

    assigns =
      Map.merge(assigns, %{
        span: span,
        is_expanded: is_expanded,
        has_children: has_children,
        indent_px: indent_px
      })

    ~H"""
    <div class="span-row" phx-click="select_span" phx-value-span_id={@span.id}>
      <div class="span-label" style={"padding-left: #{@indent_px}px"}>
        <%= if @has_children do %>
          <span class="expand-toggle" phx-click="toggle_span" phx-value-span_id={@span.id}>
            <%= if @is_expanded, do: "▼", else: "▶" %>
          </span>
        <% else %>
          <span class="expand-toggle"></span>
        <% end %>
        <span class="span-name"><%= @span.name %></span>
        <span class="span-duration"><%= format_duration(@span.duration_ms) %></span>
      </div>
      <div class="span-timeline">
        <div class="timeline-bar" style={calculate_bar_style(@span, assigns.trace_spans)}></div>
      </div>
    </div>

    <%= if @is_expanded && @has_children do %>
      <%= for child <- @span.children do %>
        <%= render_span(assigns, child, depth + 1) %>
      <% end %>
    <% end %>
    """
  end
end
