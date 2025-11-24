defmodule AshAgent.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AshAgent.ProviderRegistry,
      AshAgent.RuntimeRegistry
    ]

    opts = [strategy: :one_for_one, name: AshAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
