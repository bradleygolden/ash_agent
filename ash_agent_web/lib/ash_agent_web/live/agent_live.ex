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
    agent_tools = if agent, do: introspect_agent_tools(agent), else: []

    socket =
      socket
      |> assign(:agent, agent)
      |> assign(:metrics, metrics)
      |> assign(:current_calls, [])
      |> assign(:call_history, [])
      |> assign(:timeline_events, [])
      |> assign(:calling_agent, false)
      |> assign(:agent_inputs, agent_inputs)
      |> assign(:form_data, agent_inputs.form_data)
      |> assign(:agent_tools, agent_tools)
      |> assign(:show_tools_panel, false)

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
      {:ok, response, input_data} ->
        # Add agent response event to timeline
        response_event = %{
          type: :agent_response,
          timestamp: System.system_time(:millisecond),
          response: response,
          input_data: input_data,
          status: :success
        }

        {:noreply, update(socket, :timeline_events, &(&1 ++ [response_event]))}

      {:error, error, input_data} ->
        # Add error event to timeline
        error_event = %{
          type: :agent_error,
          timestamp: System.system_time(:millisecond),
          error: inspect(error),
          input_data: input_data,
          status: :error
        }

        socket =
          socket
          |> update(:timeline_events, &(&1 ++ [error_event]))
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
  def handle_event("toggle_details", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    updated_history =
      socket.assigns.conversation_history
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        if idx == index do
          Map.update(entry, :show_details, false, &(!&1))
        else
          entry
        end
      end)

    {:noreply, assign(socket, :conversation_history, updated_history)}
  end

  @impl true
  def handle_event("toggle_call_details", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    updated_calls =
      socket.assigns.call_history
      |> Enum.with_index()
      |> Enum.map(fn {call, idx} ->
        if idx == index do
          Map.update(call, :show_details, false, &(!&1))
        else
          call
        end
      end)

    {:noreply, assign(socket, :call_history, updated_calls)}
  end

  @impl true
  def handle_event("toggle_iterations", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    updated_calls =
      socket.assigns.call_history
      |> Enum.with_index()
      |> Enum.map(fn {call, idx} ->
        if idx == index do
          Map.update(call, :show_iterations, false, &(!&1))
        else
          call
        end
      end)

    {:noreply, assign(socket, :call_history, updated_calls)}
  end

  @impl true
  def handle_event("toggle_iteration_details", %{"call_index" => call_idx_str, "iteration_index" => iter_idx_str}, socket) do
    call_idx = String.to_integer(call_idx_str)
    iter_idx = String.to_integer(iter_idx_str)

    updated_calls =
      socket.assigns.call_history
      |> Enum.with_index()
      |> Enum.map(fn {call, idx} ->
        if idx == call_idx && call[:context] && call.context[:iterations] do
          updated_iterations =
            call.context.iterations
            |> Enum.with_index()
            |> Enum.map(fn {iteration, i_idx} ->
              if i_idx == iter_idx do
                Map.update(iteration, :show_details, false, &(!&1))
              else
                iteration
              end
            end)

          put_in(call, [:context, :iterations], updated_iterations)
        else
          call
        end
      end)

    {:noreply, assign(socket, :call_history, updated_calls)}
  end

  @impl true
  def handle_event("call_agent", params, socket) do
    agent = socket.assigns.agent
    arguments = socket.assigns.agent_inputs.arguments

    input_map = build_input_map(params, arguments)

    if agent && valid_inputs?(input_map, arguments) do
      # Add user input event to timeline
      user_event = %{
        type: :user_input,
        timestamp: System.system_time(:millisecond),
        input_data: input_map,
        input_summary: format_input_summary(input_map, arguments)
      }

      socket =
        socket
        |> assign(:calling_agent, true)
        |> update(:timeline_events, &(&1 ++ [user_event]))

      # Add "agent thinking" event
      thinking_event = %{
        type: :agent_thinking,
        timestamp: System.system_time(:millisecond),
        iteration: 1
      }

      socket = update(socket, :timeline_events, &(&1 ++ [thinking_event]))

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
    <div class="chat-container">
      <div class="chat-header">
        <div class="header-left">
          <a href="/" class="breadcrumb-link">← All Agents</a>
          <%= if @agent do %>
            <h1 class="agent-name"><%= inspect(@agent) %></h1>
          <% end %>
        </div>
        <div class="header-right">
          <button phx-click="toggle_tools_panel" class="tools-button">
            🔧 Tools (<%= length(@agent_tools) %>)
          </button>
        </div>
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

        <%= if length(@agent_tools) > 0 do %>
          <div class="section tools-section">
            <h3>Available Tools (<%= length(@agent_tools) %>)</h3>
            <div class="tools-list">
              <%= for tool <- @agent_tools do %>
                <div class="tool-card">
                  <div class="tool-header">
                    <code class="tool-name"><%= tool.name %></code>
                  </div>
                  <%= if tool.description do %>
                    <div class="tool-description"><%= tool.description %></div>
                  <% end %>
                  <%= if length(tool.parameters) > 0 do %>
                    <div class="tool-parameters">
                      <div class="parameters-label">Parameters:</div>
                      <ul class="parameters-list">
                        <%= for {param_name, param_opts} <- tool.parameters do %>
                          <li class="parameter-item">
                            <code class="parameter-name"><%= param_name %></code>
                            <span class="parameter-type">: <%= Keyword.get(param_opts, :type, :any) %></span>
                            <%= if !Keyword.get(param_opts, :required, false) do %>
                              <span class="parameter-optional"> (optional)</span>
                              <%= if Keyword.has_key?(param_opts, :default) do %>
                                <span class="parameter-default"> = <%= inspect(Keyword.get(param_opts, :default)) %></span>
                              <% end %>
                            <% end %>
                          </li>
                        <% end %>
                      </ul>
                    </div>
                  <% else %>
                    <div class="tool-no-params">No parameters</div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if length(@conversation_history) > 0 do %>
          <div class="section">
            <h3>Conversation History</h3>
            <div class="conversation-list">
              <%= for {entry, idx} <- Enum.with_index(@conversation_history) do %>
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

                  <button phx-click="toggle_details" phx-value-index={idx} class="details-toggle">
                    <%= if entry.show_details do %>
                      ▼ Hide Details
                    <% else %>
                      ▶ Show Request/Response Details
                    <% end %>
                  </button>

                  <%= if entry.show_details do %>
                    <div class="details-panel">
                      <div class="detail-section">
                        <div class="detail-header">Request Input:</div>
                        <pre class="detail-content"><%= inspect(entry.input_data, pretty: true, limit: :infinity) %></pre>
                      </div>
                      <%= if entry[:response_data] do %>
                        <div class="detail-section">
                          <div class="detail-header">Response Data:</div>
                          <pre class="detail-content"><%= inspect(entry.response_data, pretty: true, limit: :infinity) %></pre>
                        </div>
                      <% end %>
                      <%= if entry[:error] do %>
                        <div class="detail-section">
                          <div class="detail-header">Error Details:</div>
                          <pre class="detail-content"><%= entry.error %></pre>
                        </div>
                      <% end %>
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
              <%= for {call, idx} <- Enum.with_index(@call_history) do %>
                <div class="call-item-wrapper">
                  <div class="call-item">
                    <span class={"status-indicator #{call.status}"}></span>
                    <div class="call-info">
                      <div class="call-details">
                        <span class="call-status"><%= call.status %></span>
                        <span class="call-duration"><%= call.duration_ms %>ms</span>
                        <%= if call[:usage] do %>
                          <span class="call-tokens">
                            <%= get_total_tokens(call.usage) %> tokens
                            <%= if call.usage[:input_tokens] do %>
                              (in: <%= call.usage.input_tokens %>, out: <%= call.usage.output_tokens %>)
                            <% end %>
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

                  <button phx-click="toggle_call_details" phx-value-index={idx} class="details-toggle">
                    <%= if call[:show_details] do %>
                      ▼ Hide Call Details
                    <% else %>
                      ▶ Show Call Details (Request/Response/Tokens)
                    <% end %>
                  </button>

                  <%= if call[:show_details] do %>
                    <div class="details-panel">
                      <%= if call[:input] do %>
                        <div class="detail-section">
                          <div class="detail-header">Request Input:</div>
                          <pre class="detail-content"><%= inspect(call.input, pretty: true, limit: :infinity) %></pre>
                        </div>
                      <% end %>

                      <%= if call[:result] do %>
                        <div class="detail-section">
                          <div class="detail-header">Response Result:</div>
                          <pre class="detail-content"><%= inspect(call.result, pretty: true, limit: :infinity) %></pre>
                        </div>
                      <% end %>

                      <%= if call[:usage] do %>
                        <div class="detail-section">
                          <div class="detail-header">Token Usage:</div>
                          <pre class="detail-content"><%= inspect(call.usage, pretty: true) %></pre>
                        </div>
                      <% end %>

                      <%= if call[:client] do %>
                        <div class="detail-section">
                          <div class="detail-header">LLM Client:</div>
                          <pre class="detail-content"><%= inspect(call.client, pretty: true) %></pre>
                        </div>
                      <% end %>

                      <%= if call[:provider] do %>
                        <div class="detail-section">
                          <div class="detail-header">Provider:</div>
                          <pre class="detail-content"><%= inspect(call.provider, pretty: true) %></pre>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <%= if has_iterations?(call) do %>
                    <button phx-click="toggle_iterations" phx-value-index={idx} class="details-toggle iterations-toggle">
                      <%= if call[:show_iterations] do %>
                        ▼ Hide Execution Details (<%= get_iteration_count(call) %> iterations)
                      <% else %>
                        ▶ Show Execution Details (<%= get_iteration_count(call) %> iterations)
                      <% end %>
                    </button>

                    <%= if call[:show_iterations] do %>
                      <div class="iterations-panel">
                        <div class="iterations-header">
                          <div class="iterations-summary">
                            <strong>Total Iterations:</strong> <%= call.context.total_iterations %>
                            <%= if call.context[:cumulative_tokens] do %>
                              | <strong>Cumulative Tokens:</strong>
                              In: <%= call.context.cumulative_tokens[:input_tokens] || 0 %>,
                              Out: <%= call.context.cumulative_tokens[:output_tokens] || 0 %>,
                              Total: <%= call.context.cumulative_tokens[:total_tokens] || 0 %>
                            <% end %>
                          </div>
                        </div>

                        <%= for {iteration, iter_idx} <- Enum.with_index(call.context.iterations) do %>
                          <div class="iteration-item">
                            <div class="iteration-header">
                              <div class="iteration-title">
                                <strong>Iteration <%= iteration.number %></strong>
                                <span class="iteration-meta">
                                  <%= render_iteration_summary(iteration) %>
                                </span>
                              </div>
                              <div class="iteration-time">
                                Started: <%= format_datetime(iteration.started_at) %>
                                <%= if iteration.completed_at do %>
                                  | Completed: <%= format_datetime(iteration.completed_at) %>
                                <% end %>
                              </div>
                            </div>

                            <button
                              phx-click="toggle_iteration_details"
                              phx-value-call_index={idx}
                              phx-value-iteration_index={iter_idx}
                              class="iteration-toggle"
                            >
                              <%= if iteration[:show_details] do %>
                                ▼ Hide Messages & Tool Calls
                              <% else %>
                                ▶ Show Messages & Tool Calls
                              <% end %>
                            </button>

                            <%= if iteration[:show_details] do %>
                              <div class="iteration-details">
                                <%= if length(iteration.messages) > 0 do %>
                                  <div class="messages-section">
                                    <div class="section-label">Messages:</div>
                                    <%= for {message, msg_idx} <- Enum.with_index(iteration.messages) do %>
                                      <div class="message-item">
                                        <div class="message-role"><%= format_role(message.role) %>:</div>
                                        <div class="message-content">
                                          <%= render_message_content(message.content) %>
                                        </div>
                                        <%= if message[:tool_calls] && length(message.tool_calls) > 0 do %>
                                          <div class="message-tool-calls">
                                            <div class="tool-calls-label">Tool Calls:</div>
                                            <%= for tool_call <- message.tool_calls do %>
                                              <div class="tool-call-item">
                                                <code><%= tool_call.name %></code> (ID: <%= tool_call.id %>)
                                                <pre class="tool-call-args"><%= inspect(tool_call.arguments, pretty: true) %></pre>
                                              </div>
                                            <% end %>
                                          </div>
                                        <% end %>
                                      </div>
                                    <% end %>
                                  </div>
                                <% end %>

                                <%= if iteration.metadata && map_size(iteration.metadata) > 0 do %>
                                  <div class="metadata-section">
                                    <div class="section-label">Iteration Metadata:</div>
                                    <pre class="metadata-content"><%= inspect(iteration.metadata, pretty: true) %></pre>
                                  </div>
                                <% end %>
                              </div>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>

      <style>
        .agent-dashboard { padding: 2rem; font-family: system-ui, -apple-system, sans-serif; max-width: 1200px; margin: 0 auto; }

        .breadcrumb { margin-bottom: 1rem; }
        .breadcrumb-link {
          color: #3b82f6;
          text-decoration: none;
          font-size: 0.875rem;
          font-weight: 500;
          transition: color 0.2s;
        }
        .breadcrumb-link:hover { color: #2563eb; }

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
        .conversation-response { margin-bottom: 1rem; }
        .conversation-error { background: #fee; padding: 1rem; border-radius: 6px; margin-bottom: 1rem; }
        .conversation-label { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; color: #666; margin-bottom: 0.5rem; letter-spacing: 0.5px; }
        .conversation-content { color: #1a1a1a; line-height: 1.6; white-space: pre-wrap; }
        .conversation-timestamp { font-size: 0.75rem; color: #999; margin-top: 0.5rem; }

        .details-toggle {
          background: #f3f4f6;
          border: 1px solid #d1d5db;
          border-radius: 4px;
          padding: 0.5rem 1rem;
          font-size: 0.875rem;
          font-weight: 500;
          color: #374151;
          cursor: pointer;
          transition: all 0.2s;
          width: 100%;
          text-align: left;
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .details-toggle:hover { background: #e5e7eb; }

        .details-panel {
          margin-top: 1rem;
          border-top: 1px solid #e5e5e5;
          padding-top: 1rem;
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }
        .detail-section {
          background: #f9fafb;
          border: 1px solid #e5e7eb;
          border-radius: 6px;
          padding: 1rem;
        }
        .detail-header {
          font-size: 0.875rem;
          font-weight: 600;
          color: #374151;
          margin-bottom: 0.5rem;
        }
        .detail-content {
          background: #1f2937;
          color: #e5e7eb;
          padding: 1rem;
          border-radius: 4px;
          overflow-x: auto;
          font-size: 0.875rem;
          line-height: 1.5;
          font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
          margin: 0;
        }

        .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
        .metric-card { background: white; border: 1px solid #e5e5e5; border-radius: 8px; padding: 1.5rem; }
        .metric-label { font-size: 0.875rem; color: #666; margin-bottom: 0.5rem; text-transform: uppercase; letter-spacing: 0.5px; }
        .metric-value { font-size: 2rem; font-weight: 600; color: #1a1a1a; }
        .metric-value.error { color: #dc2626; }

        .section { margin-bottom: 2rem; }
        .section h3 { margin: 0 0 1rem; font-size: 1.25rem; color: #1a1a1a; }

        .calls-list { display: flex; flex-direction: column; gap: 1rem; }
        .call-item-wrapper { background: white; border: 1px solid #e5e5e5; border-radius: 8px; padding: 1rem; }
        .call-item { display: flex; align-items: flex-start; gap: 1rem; margin-bottom: 0.5rem; }
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

        .tools-section { background: white; border: 1px solid #e5e5e5; border-radius: 8px; padding: 1.5rem; margin-bottom: 2rem; }
        .tools-section h3 { margin: 0 0 1rem; color: #1a1a1a; }
        .tools-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem; }
        .tool-card { background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 6px; padding: 1rem; }
        .tool-header { margin-bottom: 0.5rem; }
        .tool-name { font-size: 1rem; font-weight: 600; color: #7c3aed; background: #f5f3ff; padding: 0.25rem 0.5rem; border-radius: 4px; }
        .tool-description { font-size: 0.875rem; color: #4b5563; margin-bottom: 0.75rem; line-height: 1.5; }
        .tool-parameters { margin-top: 0.75rem; }
        .parameters-label { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; color: #6b7280; letter-spacing: 0.5px; margin-bottom: 0.5rem; }
        .parameters-list { margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 0.5rem; }
        .parameter-item { font-size: 0.875rem; }
        .parameter-name { font-weight: 600; color: #1f2937; background: #e5e7eb; padding: 0.125rem 0.375rem; border-radius: 3px; }
        .parameter-type { color: #059669; font-style: italic; }
        .parameter-optional { color: #6b7280; font-size: 0.75rem; }
        .parameter-default { color: #9ca3af; font-family: monospace; font-size: 0.75rem; }
        .tool-no-params { font-size: 0.875rem; color: #9ca3af; font-style: italic; }

        .iterations-toggle {
          margin-top: 0.5rem;
          background: #eff6ff;
          border: 1px solid #93c5fd;
        }
        .iterations-toggle:hover { background: #dbeafe; }

        .iterations-panel {
          margin-top: 1rem;
          padding: 1rem;
          background: #fafafa;
          border: 1px solid #e0e0e0;
          border-radius: 6px;
        }

        .iterations-header {
          margin-bottom: 1rem;
          padding-bottom: 0.75rem;
          border-bottom: 2px solid #d1d5db;
        }

        .iterations-summary {
          font-size: 0.875rem;
          color: #374151;
          line-height: 1.6;
        }

        .iteration-item {
          background: white;
          border: 1px solid #d1d5db;
          border-radius: 6px;
          padding: 1rem;
          margin-bottom: 1rem;
        }

        .iteration-item:last-child { margin-bottom: 0; }

        .iteration-header {
          margin-bottom: 0.75rem;
        }

        .iteration-title {
          display: flex;
          align-items: baseline;
          gap: 1rem;
          margin-bottom: 0.25rem;
        }

        .iteration-meta {
          font-size: 0.875rem;
          color: #6b7280;
          font-weight: normal;
        }

        .iteration-time {
          font-size: 0.75rem;
          color: #9ca3af;
        }

        .iteration-toggle {
          background: #f9fafb;
          border: 1px solid #e5e7eb;
          border-radius: 4px;
          padding: 0.5rem 1rem;
          font-size: 0.875rem;
          font-weight: 500;
          color: #374151;
          cursor: pointer;
          transition: all 0.2s;
          width: 100%;
          text-align: left;
        }

        .iteration-toggle:hover { background: #f3f4f6; }

        .iteration-details {
          margin-top: 1rem;
          padding-top: 1rem;
          border-top: 1px solid #e5e7eb;
        }

        .messages-section {
          margin-bottom: 1rem;
        }

        .section-label {
          font-size: 0.875rem;
          font-weight: 600;
          color: #374151;
          margin-bottom: 0.75rem;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }

        .message-item {
          background: #f9fafb;
          border: 1px solid #e5e7eb;
          border-radius: 4px;
          padding: 0.75rem;
          margin-bottom: 0.75rem;
        }

        .message-item:last-child { margin-bottom: 0; }

        .message-role {
          font-size: 0.75rem;
          font-weight: 600;
          color: #7c3aed;
          text-transform: uppercase;
          margin-bottom: 0.5rem;
          letter-spacing: 0.5px;
        }

        .message-content {
          color: #1f2937;
          font-size: 0.875rem;
          line-height: 1.6;
          white-space: pre-wrap;
          word-break: break-word;
        }

        .message-tool-calls {
          margin-top: 0.75rem;
          padding-top: 0.75rem;
          border-top: 1px solid #e5e7eb;
        }

        .tool-calls-label {
          font-size: 0.75rem;
          font-weight: 600;
          color: #059669;
          text-transform: uppercase;
          margin-bottom: 0.5rem;
          letter-spacing: 0.5px;
        }

        .tool-call-item {
          background: #f0fdf4;
          border: 1px solid #86efac;
          border-radius: 4px;
          padding: 0.5rem;
          margin-bottom: 0.5rem;
          font-size: 0.875rem;
        }

        .tool-call-item:last-child { margin-bottom: 0; }

        .tool-call-item code {
          font-weight: 600;
          color: #059669;
        }

        .tool-call-args {
          margin-top: 0.5rem;
          background: #1f2937;
          color: #e5e7eb;
          padding: 0.5rem;
          border-radius: 3px;
          font-size: 0.75rem;
          overflow-x: auto;
        }

        .metadata-section {
          margin-top: 1rem;
          padding-top: 1rem;
          border-top: 1px solid #e5e7eb;
        }

        .metadata-content {
          background: #1f2937;
          color: #e5e7eb;
          padding: 0.75rem;
          border-radius: 4px;
          font-size: 0.75rem;
          overflow-x: auto;
          line-height: 1.5;
        }
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

  defp render_iteration_summary(iteration) do
    message_count = length(iteration.messages || [])
    tool_call_count = length(iteration.tool_calls || [])

    parts = []
    parts = if message_count > 0, do: parts ++ ["#{message_count} messages"], else: parts
    parts = if tool_call_count > 0, do: parts ++ ["#{tool_call_count} tool calls"], else: parts

    Enum.join(parts, ", ")
  end

  defp format_role(role) when is_atom(role), do: role |> to_string() |> String.capitalize()
  defp format_role(role) when is_binary(role), do: String.capitalize(role)
  defp format_role(_), do: "Unknown"

  defp render_message_content(content) when is_binary(content) do
    if String.length(content) > 200 do
      String.slice(content, 0, 200) <> "..."
    else
      content
    end
  end

  defp render_message_content(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{type: :tool_result, tool_use_id: id, content: c} ->
        "Tool Result [#{id}]: #{inspect(c, limit: 100)}"
      item ->
        inspect(item, limit: 100)
    end)
    |> Enum.join("\n")
  end

  defp render_message_content(content), do: inspect(content, limit: 200)

  defp has_iterations?(call) do
    call[:context] && call.context[:iterations] && length(call.context.iterations) > 0
  end

  defp get_iteration_count(call) do
    if has_iterations?(call) do
      call.context[:total_iterations] || length(call.context.iterations)
    else
      0
    end
  end

  defp format_datetime(nil), do: "N/A"
  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end
  defp format_datetime(_), do: "N/A"
end
