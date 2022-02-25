defmodule Hologram.E2EWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hologram_e2e

  @session_options [
    key: "_hologram_e2e_key",
    signing_salt: "K3oja7Gn",
    store: :cookie
  ]

  socket "/hologram", Hologram.Runtime.Socket

  plug Plug.Static,
    at: "/",
    from: :hologram_e2e,
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
