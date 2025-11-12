import Config

config :ash_agent_web, AshAgentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ash_agent_web_test_secret_key_base",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
