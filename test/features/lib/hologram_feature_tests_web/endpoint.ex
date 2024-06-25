defmodule HologramFeatureTestsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hologram_feature_tests
  use Hologram.Endpoint

  @session_options [
    key: "phoenix_session",
    same_site: "Lax",
    signing_salt: "KEknrT4D",
    store: :cookie
  ]

  hologram_socket()

  plug Plug.Static,
    at: "/",
    from: :hologram_feature_tests,
    gzip: false,
    only: ~w(assets fonts hologram images favicon.ico robots.txt)

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    json_decoder: Phoenix.json_library(),
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"]

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug Hologram.Router
end
