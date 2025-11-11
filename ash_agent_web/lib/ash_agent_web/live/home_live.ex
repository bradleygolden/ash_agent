defmodule AshAgentWeb.HomeLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    agents = discover_agents()

    socket =
      socket
      |> assign(:agents, agents)
      |> assign(:filter, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :filter, query)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="home-dashboard">
      <div class="header">
        <h1>AshAgent Dashboard</h1>
        <p class="subtitle">Monitor and interact with your agents</p>
      </div>

      <%= if length(@agents) > 0 do %>
        <div class="search-section">
          <input
            type="text"
            placeholder="Search agents..."
            value={@filter}
            phx-keyup="filter"
            phx-debounce="300"
            class="search-input"
          />
        </div>

        <div class="agents-grid">
          <%= for agent <- filter_agents(@agents, @filter) do %>
            <a href={"/agents/#{agent.module}"} class="agent-card">
              <div class="agent-icon">🤖</div>
              <div class="agent-info">
                <h3 class="agent-name"><%= agent.short_name %></h3>
                <div class="agent-module"><%= inspect(agent.module) %></div>
                <%= if agent.input_count > 0 do %>
                  <div class="agent-meta">
                    <span class="meta-item">📝 <%= agent.input_count %> input<%= if agent.input_count != 1, do: "s" %></span>
                  </div>
                <% else %>
                  <div class="agent-meta">
                    <span class="meta-item">⚡ No inputs</span>
                  </div>
                <% end %>
                <%= if agent.tool_count > 0 do %>
                  <div class="agent-meta">
                    <span class="meta-item">🔧 <%= agent.tool_count %> tool<%= if agent.tool_count != 1, do: "s" %></span>
                  </div>
                <% end %>
              </div>
              <div class="arrow">→</div>
            </a>
          <% end %>
        </div>
      <% else %>
        <div class="empty-state">
          <div class="empty-icon">🤷</div>
          <h2>No Agents Found</h2>
          <p>No AshAgent resources are currently loaded in the system.</p>
          <p class="hint">Make sure your agent modules are compiled and loaded.</p>
        </div>
      <% end %>

      <style>
        .home-dashboard { padding: 2rem; font-family: system-ui, -apple-system, sans-serif; max-width: 1200px; margin: 0 auto; }
        .header { margin-bottom: 2rem; text-align: center; }
        .header h1 { margin: 0; font-size: 2.5rem; color: #1a1a1a; }
        .subtitle { margin: 0.5rem 0 0; font-size: 1.125rem; color: #6b7280; }

        .search-section { margin-bottom: 2rem; }
        .search-input {
          width: 100%;
          max-width: 500px;
          padding: 0.75rem 1rem;
          border: 1px solid #d1d5db;
          border-radius: 8px;
          font-size: 1rem;
          display: block;
          margin: 0 auto;
        }
        .search-input:focus {
          outline: none;
          border-color: #3b82f6;
          box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
        }

        .agents-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
          gap: 1.5rem;
        }

        .agent-card {
          background: white;
          border: 1px solid #e5e5e5;
          border-radius: 12px;
          padding: 1.5rem;
          display: flex;
          align-items: flex-start;
          gap: 1rem;
          text-decoration: none;
          color: inherit;
          transition: all 0.2s;
          cursor: pointer;
        }
        .agent-card:hover {
          border-color: #3b82f6;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
          transform: translateY(-2px);
        }

        .agent-icon {
          font-size: 2.5rem;
          line-height: 1;
        }

        .agent-info {
          flex: 1;
          min-width: 0;
        }

        .agent-name {
          margin: 0 0 0.25rem;
          font-size: 1.25rem;
          font-weight: 600;
          color: #1a1a1a;
        }

        .agent-module {
          font-size: 0.75rem;
          color: #6b7280;
          font-family: monospace;
          margin-bottom: 0.75rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .agent-meta {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
          margin-top: 0.5rem;
        }

        .meta-item {
          font-size: 0.875rem;
          color: #4b5563;
          background: #f3f4f6;
          padding: 0.25rem 0.5rem;
          border-radius: 4px;
        }

        .arrow {
          font-size: 1.5rem;
          color: #9ca3af;
          transition: transform 0.2s;
        }
        .agent-card:hover .arrow {
          transform: translateX(4px);
          color: #3b82f6;
        }

        .empty-state {
          text-align: center;
          padding: 4rem 2rem;
          color: #6b7280;
        }
        .empty-icon {
          font-size: 4rem;
          margin-bottom: 1rem;
        }
        .empty-state h2 {
          margin: 0 0 0.5rem;
          color: #374151;
          font-size: 1.5rem;
        }
        .empty-state p {
          margin: 0.5rem 0;
          font-size: 1rem;
        }
        .hint {
          font-size: 0.875rem;
          color: #9ca3af;
        }
      </style>
    </div>
    """
  end

  defp discover_agents do
    :code.all_loaded()
    |> Enum.map(fn {module, _} -> module end)
    |> Enum.filter(&agent_module?/1)
    |> Enum.map(&build_agent_info/1)
    |> Enum.sort_by(& &1.short_name)
  end

  defp agent_module?(module) do
    try do
      Code.ensure_loaded?(module) &&
        function_exported?(module, :spark_is?, 0) &&
        module.spark_is?() == Ash.Resource &&
        AshAgent.Resource in Spark.extensions(module)
    rescue
      _ -> false
    end
  end

  defp build_agent_info(module) do
    action = Ash.Resource.Info.action(module, :call)
    tools = get_tools(module)

    input_count =
      case action do
        nil -> 0
        action -> length(action.arguments)
      end

    short_name =
      module
      |> Module.split()
      |> List.last()

    %{
      module: module,
      short_name: short_name,
      input_count: input_count,
      tool_count: length(tools)
    }
  end

  defp get_tools(module) do
    try do
      AshAgent.Info.tools(module)
    rescue
      _ -> []
    end
  end

  defp filter_agents(agents, "") do
    agents
  end

  defp filter_agents(agents, filter) do
    filter_lower = String.downcase(filter)

    Enum.filter(agents, fn agent ->
      String.contains?(String.downcase(agent.short_name), filter_lower) ||
        String.contains?(String.downcase(to_string(agent.module)), filter_lower)
    end)
  end
end
