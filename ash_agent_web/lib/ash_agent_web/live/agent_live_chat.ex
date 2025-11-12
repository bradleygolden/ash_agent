defmodule AshAgentWeb.AgentLiveChat do
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
      |> assign(:timeline_events, [])
      |> assign(:calling_agent, false)
      |> assign(:agent_inputs, agent_inputs)
      |> assign(:form_data, agent_inputs.form_data)
      |> assign(:agent_tools, agent_tools)
      |> assign(:show_tools_panel, false)
      |> assign(:show_trace_panel, false)
      |> assign(:trace_spans, [])
      |> assign(:expanded_spans, MapSet.new())

    {:ok, socket}
  end

  @impl true
  def handle_info({:call_started, call_data}, socket) do
    # Initialize trace with empty root span when agent call starts
    start_time = System.system_time(:millisecond)

    root_span = %{
      id: "root",
      parent_id: nil,
      name: "Agent Execution",
      type: :agent,
      start_time: start_time,
      end_time: nil,
      duration_ms: 0,
      status: :running,
      metadata: %{agent: call_data.agent},
      children: []
    }

    socket =
      socket
      |> assign(:trace_spans, [root_span])
      |> assign(:trace_start_time, start_time)
      |> assign(:expanded_spans, MapSet.new(["root"]))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:call_completed, call_data}, socket) do
    # Finalize the root span with completion time and status
    trace_spans = socket.assigns.trace_spans
    end_time = call_data.completed_at

    updated_spans = if length(trace_spans) > 0 do
      update_span(trace_spans, "root", fn span ->
        duration = end_time - span.start_time
        %{span |
          end_time: end_time,
          duration_ms: duration,
          status: call_data.status,
          metadata: Map.put(span.metadata, :total_tokens, call_data.context[:cumulative_tokens])
        }
      end)
    else
      # Fallback: build from call_data if trace wasn't started
      if call_data[:context] && call_data.context[:iterations] do
        build_trace_spans(call_data)
      else
        []
      end
    end

    socket = assign(socket, :trace_spans, updated_spans)

    # Add token usage summary event to timeline if token data is available
    socket = if call_data[:context] && call_data.context[:cumulative_tokens] do
      cumulative = call_data.context.cumulative_tokens
      has_tokens = cumulative.total_tokens > 0 || cumulative.input_tokens > 0 || cumulative.output_tokens > 0

      if has_tokens do
        token_summary_event = %{
          type: :token_summary,
          timestamp: call_data.completed_at,
          cumulative_tokens: cumulative,
          iterations: call_data.context[:iterations] || []
        }

        update(socket, :timeline_events, &(&1 ++ [token_summary_event]))
      else
        socket
      end
    else
      socket
    end

    {:noreply, assign(socket, :trace_spans, trace_spans)}
  end

  @impl true
  def handle_info({:call_failed, _call_data}, socket), do: {:noreply, socket}
  @impl true
  def handle_info({:token_warning, _metadata}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:iteration_started, data}, socket) do
    iteration_event = %{
      type: :iteration_start,
      timestamp: data.timestamp,
      iteration: data.iteration
    }

    # Remove the initial generic "thinking" event and add specific iteration event
    updated_events =
      socket.assigns.timeline_events
      |> Enum.reject(&(&1.type == :agent_thinking))
      |> Kernel.++([iteration_event])

    # Add iteration span to trace in real-time
    socket = add_iteration_to_trace(socket, data)

    {:noreply, assign(socket, :timeline_events, updated_events)}
  end

  @impl true
  def handle_info({:tool_call_started, data}, socket) do
    tool_call_event = %{
      type: :tool_call,
      timestamp: data.timestamp,
      iteration: data.iteration,
      tool_name: data.tool_name,
      tool_id: data.tool_id,
      arguments: data.arguments,
      status: :loading,
      result: nil,
      error: nil
    }

    # Add tool call span to trace in real-time
    socket = add_tool_call_to_trace(socket, data)

    {:noreply, update(socket, :timeline_events, &(&1 ++ [tool_call_event]))}
  end

  @impl true
  def handle_info({:tool_call_completed, data}, socket) do
    # Find and update the existing tool call event
    updated_events = Enum.map(socket.assigns.timeline_events, fn event ->
      if event.type == :tool_call && event.tool_id == data.tool_id do
        # Calculate duration in milliseconds
        duration_ms = if Map.has_key?(event, :timestamp) do
          data.timestamp - event.timestamp
        else
          0
        end

        event
        |> Map.put(:status, data.status)
        |> Map.put(:result, data.result)
        |> Map.put(:error, data.error)
        |> Map.put(:duration_ms, duration_ms)
      else
        event
      end
    end)

    # Update tool call span completion in trace
    socket = update_tool_call_in_trace(socket, data)

    {:noreply, assign(socket, :timeline_events, updated_events)}
  end

  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> assign(:calling_agent, false)
      |> assign(:form_data, socket.assigns.agent_inputs.form_data)

    case result do
      {:ok, response, input_data} ->
        response_event = %{
          type: :agent_response,
          timestamp: System.system_time(:millisecond),
          response: response,
          input_data: input_data,
          status: :success
        }

        # Remove the thinking event and add the response
        updated_events =
          socket.assigns.timeline_events
          |> Enum.reject(&(&1.type == :agent_thinking))
          |> Kernel.++([response_event])

        {:noreply, assign(socket, :timeline_events, updated_events)}

      {:error, error, input_data} ->
        error_event = %{
          type: :agent_error,
          timestamp: System.system_time(:millisecond),
          error: inspect(error),
          input_data: input_data,
          status: :error
        }

        # Remove the thinking event and add the error
        updated_events =
          socket.assigns.timeline_events
          |> Enum.reject(&(&1.type == :agent_thinking))
          |> Kernel.++([error_event])

        socket =
          socket
          |> assign(:timeline_events, updated_events)
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
      user_event = %{
        type: :user_input,
        timestamp: System.system_time(:millisecond),
        input_data: input_map,
        input_summary: format_input_summary(input_map, arguments)
      }

      thinking_event = %{
        type: :agent_thinking,
        timestamp: System.system_time(:millisecond),
        iteration: 1
      }

      socket =
        socket
        |> assign(:calling_agent, true)
        |> update(:timeline_events, &(&1 ++ [user_event, thinking_event]))

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
  def handle_event("toggle_tools_panel", _params, socket) do
    {:noreply, assign(socket, :show_tools_panel, !socket.assigns.show_tools_panel)}
  end

  @impl true
  def handle_event("toggle_trace_panel", _params, socket) do
    {:noreply, assign(socket, :show_trace_panel, !socket.assigns.show_trace_panel)}
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

  # Real-time trace update helpers
  defp add_iteration_to_trace(socket, data) do
    trace_spans = socket.assigns.trace_spans

    if length(trace_spans) > 0 do
      iteration_span = %{
        id: "iteration-#{data.iteration}",
        parent_id: "root",
        name: "Iteration #{data.iteration}",
        type: :iteration,
        start_time: data.timestamp,
        end_time: nil,
        duration_ms: 0,
        status: :running,
        metadata: %{iteration: data.iteration},
        children: []
      }

      # Add iteration as child of root span
      updated_spans = update_span_children(trace_spans, "root", fn children ->
        children ++ [iteration_span]
      end)

      assign(socket, :trace_spans, updated_spans)
    else
      socket
    end
  end

  defp add_tool_call_to_trace(socket, data) do
    trace_spans = socket.assigns.trace_spans
    iteration_id = "iteration-#{data.iteration}"

    tool_span = %{
      id: "tool-#{data.tool_id}",
      parent_id: iteration_id,
      name: "Tool: #{data.tool_name}",
      type: :tool,
      start_time: data.timestamp,
      end_time: nil,
      duration_ms: 0,
      status: :running,
      metadata: %{tool_name: data.tool_name, arguments: data.arguments},
      children: []
    }

    # Add tool call as child of iteration span
    updated_spans = update_span_children(trace_spans, iteration_id, fn children ->
      children ++ [tool_span]
    end)

    assign(socket, :trace_spans, updated_spans)
  end

  defp update_tool_call_in_trace(socket, data) do
    trace_spans = socket.assigns.trace_spans
    tool_id = "tool-#{data.tool_id}"

    # Find the tool call start time from existing span
    tool_start = find_span_start_time(trace_spans, tool_id)
    duration_ms = if tool_start, do: data.timestamp - tool_start, else: 0

    updated_spans = update_span(trace_spans, tool_id, fn span ->
      %{span |
        end_time: data.timestamp,
        duration_ms: duration_ms,
        status: if(data.status == :success || data.status == :halt, do: :success, else: :error)
      }
    end)

    assign(socket, :trace_spans, updated_spans)
  end

  defp update_span_children(spans, span_id, update_fn) do
    Enum.map(spans, fn span ->
      if span.id == span_id do
        %{span | children: update_fn.(span.children)}
      else
        %{span | children: update_span_children(span.children, span_id, update_fn)}
      end
    end)
  end

  defp update_span(spans, span_id, update_fn) do
    Enum.map(spans, fn span ->
      if span.id == span_id do
        update_fn.(span)
      else
        %{span | children: update_span(span.children, span_id, update_fn)}
      end
    end)
  end

  defp find_span_start_time(spans, span_id) do
    Enum.find_value(spans, fn span ->
      cond do
        span.id == span_id -> span.start_time
        length(span.children) > 0 -> find_span_start_time(span.children, span_id)
        true -> nil
      end
    end)
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

  defp calculate_bar_style(span, all_spans) do
    # Find the root span to get total duration
    root = List.first(all_spans)

    # Use current time for running spans
    total_duration = if root.duration_ms > 0 do
      root.duration_ms
    else
      # Still running - use elapsed time
      System.system_time(:millisecond) - root.start_time
    end

    # Avoid division by zero
    if total_duration > 0 do
      # Calculate relative position and width
      relative_start = span.start_time - root.start_time

      span_duration = if span.duration_ms > 0 do
        span.duration_ms
      else
        # Still running - use elapsed time
        max(0, System.system_time(:millisecond) - span.start_time)
      end

      width_percent = (span_duration / total_duration) * 100
      left_percent = (relative_start / total_duration) * 100

      "width: #{width_percent}%; left: #{left_percent}%; background-color: #{get_span_color(span.type, span.status)}"
    else
      # Fallback for edge cases
      "width: 100%; left: 0%; background-color: #{get_span_color(span.type, span.status)}"
    end
  end

  defp get_span_color(type, status) do
    case {type, status} do
      {_, :running} -> "#f59e0b"  # Orange for running
      {:agent, :success} -> "#10b981"
      {:agent, :ok} -> "#10b981"
      {:agent, :error} -> "#ef4444"
      {:iteration, _} -> "#8b5cf6"
      {:llm, _} -> "#3b82f6"
      {:tool, :success} -> "#10b981"
      {:tool, :error} -> "#ef4444"
      {:tool, _} -> "#f59e0b"
      _ -> "#6b7280"
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

  defp format_timestamp(ts) when is_integer(ts) do
    DateTime.from_unix!(ts, :millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_timestamp(_), do: "Unknown"

  defp format_response(response) when is_binary(response), do: response

  defp format_response(response) when is_struct(response) do
    case Map.get(response, :content) || Map.get(response, :result) || Map.get(response, :output) do
      nil -> inspect(response, pretty: true)
      value -> to_string(value)
    end
  end

  defp format_response(response), do: inspect(response, pretty: true)

  defp format_tool_result(result) when is_binary(result) do
    if String.length(result) > 100 do
      String.slice(result, 0, 100) <> "..."
    else
      result
    end
  end

  defp format_tool_result(result) when is_map(result) do
    case Map.get(result, "result") || Map.get(result, :result) do
      nil -> inspect(result, limit: 100)
      value -> inspect(value, limit: 100)
    end
  end

  defp format_tool_result(result), do: inspect(result, limit: 100)

  defp format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1000 -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{div(ms, 60_000)}m #{rem(div(ms, 1000), 60)}s"
    end
  end

  defp format_duration(_), do: ""

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(_), do: "0"

  defp render_trace_span(assigns, span, depth) do
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
    <div class="trace-span-row">
      <div class="trace-span-label" style={"padding-left: #{@indent_px}px"}>
        <%= if @has_children do %>
          <span class="trace-expand-toggle" phx-click="toggle_span" phx-value-span_id={@span.id}>
            <%= if @is_expanded, do: "▼", else: "▶" %>
          </span>
        <% else %>
          <span class="trace-expand-toggle"></span>
        <% end %>
        <span class="trace-span-name"><%= @span.name %></span>
        <span class="trace-span-duration"><%= format_duration(@span.duration_ms) %></span>
      </div>
      <div class="trace-span-timeline">
        <div class="trace-timeline-bar" style={calculate_bar_style(@span, assigns.trace_spans)}></div>
      </div>
    </div>

    <%= if @is_expanded && @has_children do %>
      <%= for child <- @span.children do %>
        <%= render_trace_span(assigns, child, depth + 1) %>
      <% end %>
    <% end %>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="chat-container">
      <!-- Header -->
      <div class="chat-header">
        <div class="header-content">
          <a href="/" class="back-link">← All Agents</a>
          <h1 class="agent-title"><%= inspect(@agent) %></h1>
        </div>
        <div class="header-actions">
          <%= if length(@trace_spans) > 0 do %>
            <button phx-click="toggle_trace_panel" class="trace-toggle-btn">
              <%= if @show_trace_panel, do: "✕ Hide Trace", else: "📊 Show Trace" %>
            </button>
          <% end %>
          <button phx-click="toggle_tools_panel" class="tools-toggle-btn">
            🔧 Tools (<%= length(@agent_tools) %>)
          </button>
        </div>
      </div>

      <!-- Tools Panel (Sliding) -->
      <%= if @show_tools_panel do %>
        <div class="tools-panel">
          <div class="tools-panel-header">
            <h3>Available Tools</h3>
            <button phx-click="toggle_tools_panel" class="close-btn">✕</button>
          </div>
          <div class="tools-panel-content">
            <%= for tool <- @agent_tools do %>
              <div class="tool-item">
                <div class="tool-name"><%= tool.name %></div>
                <%= if tool.description do %>
                  <div class="tool-desc"><%= tool.description %></div>
                <% end %>
                <%= if length(tool.parameters) > 0 do %>
                  <div class="tool-params">
                    <%= for {param_name, param_opts} <- tool.parameters do %>
                      <div class="param">
                        <code><%= param_name %></code>
                        <span class="param-type"><%= Keyword.get(param_opts, :type, :any) %></span>
                        <%= if !Keyword.get(param_opts, :required, false) do %>
                          <span class="param-optional">(optional)</span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Trace Panel (Sliding) -->
      <%= if @show_trace_panel && length(@trace_spans) > 0 do %>
        <div class="trace-panel">
          <div class="trace-panel-header">
            <h3>Execution Trace</h3>
            <button phx-click="toggle_trace_panel" class="close-btn">✕</button>
          </div>
          <div class="trace-panel-content">
            <div class="trace-waterfall-header">
              <div class="trace-header-labels">Span</div>
              <div class="trace-header-timeline">Timeline</div>
            </div>
            <%= for span <- @trace_spans do %>
              <%= render_trace_span(assigns, span, 0) %>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Timeline Messages -->
      <div class="chat-timeline" id="timeline">
        <%= if length(@timeline_events) == 0 do %>
          <div class="empty-state">
            <div class="empty-icon">💬</div>
            <p>Start a conversation with the agent</p>
          </div>
        <% else %>
          <%= for event <- @timeline_events do %>
            <%= case event.type do %>
              <% :user_input -> %>
                <div class="timeline-event user-input">
                  <div class="event-badge">You</div>
                  <div class="event-content">
                    <div class="input-data-card">
                      <%= for {key, value} <- event.input_data do %>
                        <div class="data-row">
                          <span class="data-key"><%= humanize_field_name(key) %>:</span>
                          <span class="data-value"><%= inspect(value) %></span>
                        </div>
                      <% end %>
                    </div>
                    <div class="event-time"><%= format_timestamp(event.timestamp) %></div>
                  </div>
                </div>

              <% :agent_thinking -> %>
                <div class="timeline-event agent-thinking">
                  <div class="event-badge agent">Agent</div>
                  <div class="event-content">
                    <div class="thinking-indicator">
                      <span class="spinner-dot"></span>
                      <span class="spinner-dot"></span>
                      <span class="spinner-dot"></span>
                      <span>Thinking (Iteration <%= event.iteration %>)...</span>
                    </div>
                  </div>
                </div>

              <% :agent_response -> %>
                <div class="timeline-event agent-response">
                  <div class="event-badge agent">Agent</div>
                  <div class="event-content">
                    <div class="response-card">
                      <div class="response-label">Response</div>
                      <div class="response-value"><%= format_response(event.response) %></div>
                      <details class="response-details">
                        <summary>View structured output</summary>
                        <pre><%= inspect(event.response, pretty: true, limit: :infinity) %></pre>
                      </details>
                    </div>
                    <div class="event-time"><%= format_timestamp(event.timestamp) %></div>
                  </div>
                </div>

              <% :agent_error -> %>
                <div class="timeline-event agent-error">
                  <div class="event-badge error">Error</div>
                  <div class="event-content">
                    <div class="error-message"><%= event.error %></div>
                    <div class="event-time"><%= format_timestamp(event.timestamp) %></div>
                  </div>
                </div>

              <% :iteration_start -> %>
                <div class="timeline-event iteration-start">
                  <div class="event-badge agent">Agent</div>
                  <div class="event-content">
                    <div class="iteration-indicator">
                      <span class="iteration-icon">🤔</span>
                      <span>Iteration <%= event.iteration %> starting...</span>
                    </div>
                    <div class="event-time"><%= format_timestamp(event.timestamp) %></div>
                  </div>
                </div>

              <% :tool_call -> %>
                <div class={"timeline-event tool-call #{event.status}"}>
                  <div class={"event-badge tool #{event.status}"}>
                    Tool
                  </div>
                  <div class="event-content">
                    <div class="tool-call-card">
                      <div class="tool-header">
                        <span class="tool-icon">🔧</span>
                        <span class="tool-name"><%= event.tool_name %></span>
                        <%= if event.status == :loading do %>
                          <span class="loading-dots">
                            <span class="dot"></span>
                            <span class="dot"></span>
                            <span class="dot"></span>
                          </span>
                        <% else %>
                          <%= if Map.get(event, :duration_ms) do %>
                            <span class="tool-duration"><%= format_duration(event.duration_ms) %></span>
                          <% end %>
                        <% end %>
                      </div>

                      <%= if event.status != :loading do %>
                        <div class="tool-result-section">
                          <%= if event.status == :success || event.status == :halt do %>
                            <div class="tool-result-preview"><%= format_tool_result(event.result) %></div>
                            <details class="tool-result-details">
                              <summary>View full result</summary>
                              <pre><%= inspect(event.result, pretty: true, limit: :infinity) %></pre>
                            </details>
                          <% else %>
                            <div class="tool-error-message"><%= inspect(event.error) %></div>
                          <% end %>
                        </div>
                      <% end %>

                      <%= if map_size(event.arguments) > 0 && event.status == :loading do %>
                        <details class="tool-args-details">
                          <summary>View arguments</summary>
                          <pre><%= inspect(event.arguments, pretty: true) %></pre>
                        </details>
                      <% end %>
                    </div>
                    <div class="event-time"><%= format_timestamp(event.timestamp) %></div>
                  </div>
                </div>

              <% :token_summary -> %>
                <div class="timeline-event token-summary">
                  <div class="event-badge stats">📊</div>
                  <div class="event-content">
                    <div class="token-summary-card">
                      <div class="summary-header">
                        <span class="summary-title">Token Usage Summary</span>
                      </div>
                      <div class="token-stats">
                        <div class="token-stat">
                          <span class="stat-label">Total Tokens:</span>
                          <span class="stat-value"><%= format_number(event.cumulative_tokens.total_tokens) %></span>
                        </div>
                        <div class="token-stat">
                          <span class="stat-label">Input Tokens:</span>
                          <span class="stat-value"><%= format_number(event.cumulative_tokens.input_tokens) %></span>
                        </div>
                        <div class="token-stat">
                          <span class="stat-label">Output Tokens:</span>
                          <span class="stat-value"><%= format_number(event.cumulative_tokens.output_tokens) %></span>
                        </div>
                      </div>
                      <%= if length(event.iterations) > 0 do %>
                        <details class="iteration-breakdown">
                          <summary>Per-iteration breakdown (<%= length(event.iterations) %> iterations)</summary>
                          <div class="iteration-list">
                            <%= for iteration <- event.iterations do %>
                              <%= if iteration[:metadata] && iteration.metadata[:current_usage] do %>
                                <div class="iteration-token-row">
                                  <span class="iteration-num">Iteration <%= iteration.number %>:</span>
                                  <span class="iteration-tokens">
                                    <%= get_in(iteration, [:metadata, :current_usage, :total_tokens]) ||
                                        (get_in(iteration, [:metadata, :current_usage, :input_tokens]) || 0) +
                                        (get_in(iteration, [:metadata, :current_usage, :output_tokens]) || 0) %> tokens
                                    <span class="token-detail">
                                      (in: <%= get_in(iteration, [:metadata, :current_usage, :input_tokens]) || 0 %>,
                                       out: <%= get_in(iteration, [:metadata, :current_usage, :output_tokens]) || 0 %>)
                                    </span>
                                  </span>
                                </div>
                              <% end %>
                            <% end %>
                          </div>
                        </details>
                      <% end %>
                    </div>
                    <div class="event-time"><%= format_timestamp(event.timestamp) %></div>
                  </div>
                </div>

              <% _ -> %>
                <div class="timeline-event unknown">
                  <div class="event-content">
                    Unknown event type: <%= inspect(event) %>
                  </div>
                </div>
            <% end %>
          <% end %>
        <% end %>
      </div>

      <!-- Bottom Input Form -->
      <div class="chat-input-container">
        <form phx-submit="call_agent" class="chat-form">
          <%= if length(@agent_inputs.arguments) == 0 do %>
            <div class="no-args-info">This agent takes no input arguments</div>
            <button type="submit" disabled={@calling_agent} class="send-btn">
              <%= if @calling_agent do %>
                <span class="btn-spinner"></span> Calling...
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
                <%= if arg.description do %>
                  <div class="field-hint"><%= arg.description %></div>
                <% end %>
                <%= render_input_field(arg, @form_data[arg.name], @calling_agent) %>
              </div>
            <% end %>
            <button type="submit" disabled={@calling_agent} class="send-btn">
              <%= if @calling_agent do %>
                <span class="btn-spinner"></span> Sending...
              <% else %>
                Send Request →
              <% end %>
            </button>
          <% end %>
        </form>
      </div>

      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }

        .chat-container {
          display: flex;
          flex-direction: column;
          height: 100vh;
          background: #f5f5f5;
          font-family: system-ui, -apple-system, sans-serif;
        }

        .chat-header {
          background: white;
          border-bottom: 1px solid #e0e0e0;
          padding: 1rem 1.5rem;
          display: flex;
          justify-content: space-between;
          align-items: center;
          flex-shrink: 0;
        }

        .header-content {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
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

        .header-actions {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }

        .trace-link {
          background: #f3f4f6;
          border: 1px solid #d1d5db;
          border-radius: 6px;
          padding: 0.5rem 1rem;
          font-size: 0.875rem;
          color: #374151;
          text-decoration: none;
          transition: all 0.2s;
        }

        .trace-link:hover {
          background: #e5e7eb;
        }

        .tools-toggle-btn {
          background: #f3f4f6;
          border: 1px solid #d1d5db;
          border-radius: 6px;
          padding: 0.5rem 1rem;
          cursor: pointer;
          font-size: 0.875rem;
        }

        .tools-toggle-btn:hover {
          background: #e5e7eb;
        }

        .tools-panel {
          position: fixed;
          top: 0;
          right: 0;
          width: 350px;
          height: 100vh;
          background: white;
          box-shadow: -2px 0 8px rgba(0,0,0,0.1);
          z-index: 100;
          display: flex;
          flex-direction: column;
        }

        .tools-panel-header {
          padding: 1rem;
          border-bottom: 1px solid #e0e0e0;
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .close-btn {
          background: none;
          border: none;
          font-size: 1.5rem;
          cursor: pointer;
          color: #666;
        }

        .tools-panel-content {
          flex: 1;
          overflow-y: auto;
          padding: 1rem;
        }

        .tool-item {
          background: #f9fafb;
          border: 1px solid #e5e7eb;
          border-radius: 6px;
          padding: 1rem;
          margin-bottom: 0.75rem;
        }

        .tool-name {
          font-weight: 600;
          color: #7c3aed;
          margin-bottom: 0.5rem;
        }

        .tool-desc {
          font-size: 0.875rem;
          color: #666;
          margin-bottom: 0.5rem;
        }

        .tool-params {
          margin-top: 0.5rem;
          font-size: 0.75rem;
        }

        .param {
          margin: 0.25rem 0;
        }

        .param code {
          background: #e5e7eb;
          padding: 0.125rem 0.375rem;
          border-radius: 3px;
        }

        .param-type {
          color: #059669;
          font-style: italic;
          margin-left: 0.25rem;
        }

        .param-optional {
          color: #9ca3af;
          margin-left: 0.25rem;
        }

        .chat-timeline {
          flex: 1;
          overflow-y: auto;
          padding: 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }

        .empty-state {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100%;
          color: #999;
        }

        .empty-icon {
          font-size: 3rem;
          margin-bottom: 1rem;
        }

        .timeline-event {
          display: flex;
          gap: 0.75rem;
          animation: slideIn 0.3s ease-out;
        }

        @keyframes slideIn {
          from { opacity: 0; transform: translateY(10px); }
          to { opacity: 1; transform: translateY(0); }
        }

        .event-badge {
          background: #3b82f6;
          color: white;
          padding: 0.25rem 0.75rem;
          border-radius: 12px;
          font-size: 0.75rem;
          font-weight: 600;
          height: fit-content;
          white-space: nowrap;
        }

        .event-badge.agent {
          background: #7c3aed;
        }

        .event-badge.error {
          background: #dc2626;
        }

        .event-content {
          flex: 1;
          max-width: 600px;
        }

        .user-input .event-content {
          align-self: flex-start;
        }

        .input-data-card, .response-card {
          background: white;
          border: 1px solid #e0e0e0;
          border-radius: 8px;
          padding: 1rem;
          margin-bottom: 0.5rem;
        }

        .data-row {
          display: flex;
          gap: 0.5rem;
          margin-bottom: 0.5rem;
        }

        .data-row:last-child {
          margin-bottom: 0;
        }

        .data-key {
          font-weight: 600;
          color: #666;
        }

        .data-value {
          color: #1a1a1a;
        }

        .thinking-indicator {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.75rem;
          background: white;
          border: 1px solid #e0e0e0;
          border-radius: 8px;
          color: #666;
        }

        .spinner-dot {
          width: 8px;
          height: 8px;
          background: #7c3aed;
          border-radius: 50%;
          animation: bounce 1.4s infinite ease-in-out;
        }

        .spinner-dot:nth-child(1) { animation-delay: -0.32s; }
        .spinner-dot:nth-child(2) { animation-delay: -0.16s; }

        @keyframes bounce {
          0%, 80%, 100% { transform: scale(0); }
          40% { transform: scale(1); }
        }

        .response-label {
          font-size: 0.75rem;
          font-weight: 600;
          text-transform: uppercase;
          color: #666;
          margin-bottom: 0.5rem;
          letter-spacing: 0.5px;
        }

        .response-value {
          color: #1a1a1a;
          line-height: 1.6;
          margin-bottom: 0.75rem;
        }

        .response-details {
          margin-top: 0.75rem;
          padding-top: 0.75rem;
          border-top: 1px solid #e5e7eb;
        }

        .response-details summary {
          cursor: pointer;
          font-size: 0.875rem;
          color: #3b82f6;
          user-select: none;
        }

        .response-details pre {
          margin-top: 0.5rem;
          background: #1f2937;
          color: #e5e7eb;
          padding: 0.75rem;
          border-radius: 4px;
          overflow-x: auto;
          font-size: 0.75rem;
        }

        .error-message {
          background: #fee;
          border: 1px solid #fcc;
          border-radius: 8px;
          padding: 0.75rem;
          color: #dc2626;
          font-family: monospace;
          font-size: 0.875rem;
          margin-bottom: 0.5rem;
        }

        .event-time {
          font-size: 0.75rem;
          color: #999;
        }

        .chat-input-container {
          background: white;
          border-top: 1px solid #e0e0e0;
          padding: 1.5rem;
          flex-shrink: 0;
        }

        .chat-form {
          max-width: 800px;
          margin: 0 auto;
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }

        .no-args-info {
          text-align: center;
          color: #666;
          font-size: 0.875rem;
          margin-bottom: 0.5rem;
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
          margin-left: 0.25rem;
        }

        .field-hint {
          font-size: 0.75rem;
          color: #6b7280;
          font-style: italic;
        }

        .form-field input[type="text"],
        .form-field input[type="number"],
        .form-field textarea,
        .form-field select {
          padding: 0.75rem;
          border: 1px solid #d1d5db;
          border-radius: 6px;
          font-size: 1rem;
          font-family: inherit;
        }

        .form-field textarea {
          resize: vertical;
          min-height: 80px;
        }

        .form-field input:focus,
        .form-field textarea:focus,
        .form-field select:focus {
          outline: none;
          border-color: #3b82f6;
          box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
        }

        .send-btn {
          align-self: flex-end;
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

        .send-btn:hover:not(:disabled) {
          background: #2563eb;
        }

        .send-btn:disabled {
          background: #9ca3af;
          cursor: not-allowed;
        }

        .btn-spinner {
          display: inline-block;
          width: 14px;
          height: 14px;
          border: 2px solid rgba(255,255,255,0.3);
          border-top-color: white;
          border-radius: 50%;
          animation: spin 0.6s linear infinite;
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }

        .iteration-indicator {
          background: white;
          border: 1px solid #e0e0e0;
          border-radius: 8px;
          padding: 1rem;
          margin-bottom: 0.5rem;
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }

        .iteration-icon {
          font-size: 1.25rem;
        }

        /* Consolidated tool call card */
        .tool-call-card {
          background: white;
          border: 1px solid #e0e0e0;
          border-radius: 8px;
          padding: 1rem;
          margin-bottom: 0.5rem;
          transition: border-color 0.3s ease;
        }

        .tool-call.success .tool-call-card {
          border-left: 4px solid #10b981;
        }

        .tool-call.halt .tool-call-card {
          border-left: 4px solid #3b82f6;
        }

        .tool-call.error .tool-call-card {
          border-left: 4px solid #ef4444;
        }

        .tool-call.loading .tool-call-card {
          border-left: 4px solid #f59e0b;
        }

        .tool-header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          margin-bottom: 0.75rem;
        }

        .tool-icon {
          font-size: 1.125rem;
        }

        .tool-name {
          font-weight: 600;
          color: #374151;
          flex: 1;
        }

        .tool-duration {
          margin-left: auto;
          font-size: 0.75rem;
          color: #6b7280;
          font-weight: 500;
          padding: 0.125rem 0.5rem;
          background: #f3f4f6;
          border-radius: 4px;
        }

        .loading-dots {
          display: flex;
          gap: 0.25rem;
          margin-left: auto;
        }

        .loading-dots .dot {
          width: 6px;
          height: 6px;
          background: #f59e0b;
          border-radius: 50%;
          animation: pulse 1.4s infinite;
        }

        .loading-dots .dot:nth-child(1) { animation-delay: 0s; }
        .loading-dots .dot:nth-child(2) { animation-delay: 0.2s; }
        .loading-dots .dot:nth-child(3) { animation-delay: 0.4s; }

        @keyframes pulse {
          0%, 80%, 100% { opacity: 0.3; transform: scale(0.8); }
          40% { opacity: 1; transform: scale(1); }
        }

        .tool-result-section {
          margin-top: 0.75rem;
        }

        .tool-result-preview {
          color: #1a1a1a;
          font-family: monospace;
          font-size: 0.875rem;
          line-height: 1.6;
          margin-bottom: 0.75rem;
          padding: 0.5rem;
          background: #f9fafb;
          border-radius: 4px;
        }

        .tool-result-details {
          margin-top: 0.75rem;
          padding-top: 0.75rem;
          border-top: 1px solid #e5e7eb;
        }

        .tool-result-details summary {
          cursor: pointer;
          font-size: 0.875rem;
          color: #3b82f6;
          user-select: none;
        }

        .tool-result-details pre {
          margin-top: 0.5rem;
          background: #1f2937;
          color: #e5e7eb;
          padding: 0.75rem;
          border-radius: 4px;
          overflow-x: auto;
          font-size: 0.75rem;
        }

        .tool-error-message {
          color: #dc2626;
          font-family: monospace;
          font-size: 0.875rem;
          padding: 0.5rem;
          background: #fee;
          border-radius: 4px;
        }

        .tool-args-details {
          margin-top: 0.75rem;
          padding-top: 0.75rem;
          border-top: 1px solid #e5e7eb;
        }

        .tool-args-details summary {
          cursor: pointer;
          font-size: 0.875rem;
          color: #6b7280;
          user-select: none;
        }

        .tool-args-details pre {
          margin-top: 0.5rem;
          background: #f9fafb;
          color: #374151;
          padding: 0.75rem;
          border-radius: 4px;
          overflow-x: auto;
          font-size: 0.75rem;
        }

        .event-badge.tool {
          background: #059669;
        }

        .event-badge.tool.loading {
          background: #f59e0b;
        }

        .event-badge.tool.success {
          background: #10b981;
        }

        .event-badge.tool.halt {
          background: #3b82f6;
        }

        .event-badge.tool.error {
          background: #ef4444;
        }

        .tool-spinner {
          animation: spin 1s linear infinite;
        }

        /* Token Summary Styles */
        .token-summary-card {
          background: white;
          border: 1px solid #e0e0e0;
          border-left: 4px solid #8b5cf6;
          border-radius: 8px;
          padding: 1rem;
          margin-bottom: 0.5rem;
        }

        .summary-header {
          margin-bottom: 1rem;
        }

        .summary-title {
          font-weight: 600;
          font-size: 1rem;
          color: #374151;
        }

        .token-stats {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 1rem;
          margin-bottom: 0.75rem;
        }

        .token-stat {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }

        .stat-label {
          font-size: 0.75rem;
          color: #6b7280;
          font-weight: 500;
        }

        .stat-value {
          font-size: 1.25rem;
          font-weight: 700;
          color: #1f2937;
          font-family: 'SF Mono', 'Monaco', 'Courier New', monospace;
        }

        .iteration-breakdown {
          margin-top: 1rem;
          padding-top: 1rem;
          border-top: 1px solid #e5e7eb;
        }

        .iteration-breakdown summary {
          cursor: pointer;
          font-size: 0.875rem;
          color: #8b5cf6;
          font-weight: 500;
          user-select: none;
        }

        .iteration-breakdown summary:hover {
          color: #7c3aed;
        }

        .iteration-list {
          margin-top: 0.75rem;
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }

        .iteration-token-row {
          display: flex;
          justify-content: space-between;
          padding: 0.5rem;
          background: #f9fafb;
          border-radius: 4px;
          font-size: 0.875rem;
        }

        .iteration-num {
          font-weight: 600;
          color: #374151;
        }

        .iteration-tokens {
          color: #1f2937;
          font-family: 'SF Mono', 'Monaco', 'Courier New', monospace;
        }

        .token-detail {
          color: #6b7280;
          font-size: 0.75rem;
          margin-left: 0.5rem;
        }

        .event-badge.stats {
          background: #8b5cf6;
        }

        /* Trace Panel Styles */
        .trace-toggle-btn {
          background: #8b5cf6;
          color: white;
          border: 1px solid #7c3aed;
          border-radius: 6px;
          padding: 0.5rem 1rem;
          cursor: pointer;
          font-size: 0.875rem;
          transition: all 0.2s;
        }

        .trace-toggle-btn:hover {
          background: #7c3aed;
        }

        .trace-panel {
          position: fixed;
          top: 0;
          right: 0;
          width: 550px;
          height: 100vh;
          background: white;
          box-shadow: -2px 0 8px rgba(0,0,0,0.1);
          z-index: 100;
          display: flex;
          flex-direction: column;
        }

        .trace-panel-header {
          padding: 1rem;
          border-bottom: 1px solid #e0e0e0;
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .trace-panel-content {
          flex: 1;
          overflow-y: auto;
          padding: 1rem;
        }

        .trace-waterfall-header {
          display: grid;
          grid-template-columns: 200px 1fr;
          gap: 0.5rem;
          padding-bottom: 0.5rem;
          border-bottom: 2px solid #e0e0e0;
          margin-bottom: 0.5rem;
          font-size: 0.75rem;
          font-weight: 600;
          text-transform: uppercase;
          color: #6b7280;
        }

        .trace-span-row {
          display: grid;
          grid-template-columns: 200px 1fr;
          gap: 0.5rem;
          padding: 0.25rem 0;
          border-bottom: 1px solid #f3f4f6;
          font-size: 0.75rem;
        }

        .trace-span-row:hover {
          background: #f9fafb;
        }

        .trace-span-label {
          display: flex;
          align-items: center;
          gap: 0.25rem;
        }

        .trace-expand-toggle {
          width: 12px;
          height: 12px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 0.625rem;
          cursor: pointer;
          flex-shrink: 0;
        }

        .trace-span-name {
          font-weight: 500;
          color: #1f2937;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .trace-span-duration {
          font-size: 0.625rem;
          color: #6b7280;
          margin-left: auto;
          flex-shrink: 0;
        }

        .trace-span-timeline {
          position: relative;
          height: 18px;
          display: flex;
          align-items: center;
        }

        .trace-timeline-bar {
          position: absolute;
          height: 12px;
          border-radius: 2px;
          opacity: 0.9;
          transition: opacity 0.2s;
        }

        .trace-timeline-bar:hover {
          opacity: 1;
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
          <textarea
            name={to_string(@arg.name)}
            placeholder={"Enter #{humanize_field_name(@arg.name)}..."}
            disabled={@disabled}
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
          required={@arg.required}
        />
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
        <input
          type="text"
          name={to_string(@arg.name)}
          value={to_string(@value)}
          placeholder={"Enter #{humanize_field_name(@arg.name)}..."}
          disabled={@disabled}
          required={@arg.required}
        />
        """
    end
  end
end
