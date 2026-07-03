defmodule App1.Endpoint do
  use Phoenix.Endpoint, otp_app: :app_1

  @session_options [
    key: "app_1_session",
    same_site: "Lax",
    signing_salt: "Xq2pT7Vb",
    store: :cookie
  ]

  plug Plug.Static,
    at: "/",
    from: :app_1,
    gzip: false,
    only: ~w(hologram)

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId

  plug Plug.Parsers,
    json_decoder: Phoenix.json_library(),
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"]

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug Hologram.Router
end
