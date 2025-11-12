defmodule AshAgentWeb.Application do
  use Application

  @impl true
  def start(_type, _args) do
    :ets.new(:ash_agent_calls, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(:ash_agent_metrics, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(:ash_agent_call_results, [:named_table, :public, :set, read_concurrency: true])

    children = [
      {Phoenix.PubSub, name: AshAgentWeb.PubSub},
      AshAgentWeb.Telemetry,
      AshAgentWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AshAgentWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AshAgentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
