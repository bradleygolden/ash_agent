defmodule AshAgentWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ash_agent_web

  @session_options [
    store: :cookie,
    key: "_ash_agent_web_key",
    signing_salt: "ash_agent_web",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :ash_agent_web,
    gzip: false,
    only: AshAgentWeb.static_paths()

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug AshAgentWeb.Router

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
end
