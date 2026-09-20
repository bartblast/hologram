defmodule HologramCowboyTestsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hologram_cowboy_tests

  @session_options [
    key: "phoenix_session",
    same_site: "Lax",
    signing_salt: "Qm7bVt3E",
    store: :cookie
  ]

  plug Plug.Static,
    at: "/",
    from: :hologram_cowboy_tests,
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
  plug HologramCowboyTestsWeb.Router
end
