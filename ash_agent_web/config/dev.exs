import Config

config :ash_agent_web, AshAgentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "16UmpOSa3ASPMcmgFgxP3x+frJorMl4hZJKDmJ2Z5nDAsLarHK1fzyyMHetK9LXq",
  watchers: []

config :ash_agent_web, dev_routes: true

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
