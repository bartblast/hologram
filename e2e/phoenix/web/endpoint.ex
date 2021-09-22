defmodule Hologram.E2E.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :hologram

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_hologram_key",
    signing_salt: "8sGh/v5l"
  ]

  socket "/hologram", Hologram.Runtime.Socket,
    longpoll: false,
    websocket: true

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :hologram,
    gzip: false,
    only: ~w(assets fonts hologram images favicon.ico robots.txt)

  plug Plug.RequestId

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug Hologram.E2E.Web.Router
end
