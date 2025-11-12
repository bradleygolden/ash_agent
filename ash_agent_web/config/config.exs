import Config

config :ash_agent_web,
  generators: [timestamp_type: :utc_datetime]

config :ash_agent_web, :agent_apps, [:ash_agent]

config :ash_baml,
  clients: [
    default: {AshAgentWeb.BamlClient, baml_src: "priv/baml_src"},
    ollama: {AshAgent.BamlClient, baml_src: "baml_src"}
  ]

config :ash_agent_web, AshAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AshAgentWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: AshAgentWeb.PubSub,
  live_view: [signing_salt: "ash_agent_web"],
  secret_key_base: "16UmpOSa3ASPMcmgFgxP3x+frJorMl4hZJKDmJ2Z5nDAsLarHK1fzyyMHetK9LXq"

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
