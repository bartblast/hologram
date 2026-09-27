defmodule HologramEcosystemTestsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hologram_ecosystem_tests

  @session_options [
    key: "phoenix_session",
    same_site: "Lax",
    signing_salt: "Xr4kWn8P",
    store: :cookie
  ]

  plug Plug.Static,
    at: "/",
    from: :hologram_ecosystem_tests,
    gzip: false,
    only: ~w(assets fonts hologram images favicon.ico robots.txt)

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
