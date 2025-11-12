defmodule AshAgentWeb.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>AshAgent Monitor</title>
        <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.10/priv/static/phoenix.min.js">
        </script>
        <script
          src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.20.2/priv/static/phoenix_live_view.min.js"
          defer
          phx-track-static
        >
        </script>
        <style>
          * { box-sizing: border-box; }
          body { margin: 0; padding: 0; background: #f5f5f5; }
        </style>
        <script>
          window.addEventListener("load", function() {
            if (window.LiveView && window.Phoenix) {
              let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
              let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
                params: {_csrf_token: csrfToken}
              });
              liveSocket.connect();
              window.liveSocket = liveSocket;
            }
          });
        </script>
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end
end
