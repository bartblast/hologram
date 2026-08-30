defmodule HologramFeatureTestsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hologram_feature_tests

  # `max_age` makes the session cookie outlive the browser. Without it Phoenix issues a
  # browser-session cookie, and a person who closes the browser comes back as nobody - which means
  # a write they made offline waits for a sign-in that cannot happen offline. An app that wants
  # offline across a restart sets this, so this app does. Not needed by any test here (the driver's
  # reload keeps a session cookie), set because the app is the spec.
  @session_options [
    key: "phoenix_session",
    max_age: 60 * 60 * 24 * 30,
    same_site: "Lax",
    signing_salt: "KEknrT4D",
    store: :cookie
  ]

  # Before Plug.Static, which is what serves the page bundles this delays.
  plug HologramFeatureTestsWeb.Plugs.SlowPageBundle

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
  plug HologramFeatureTestsWeb.Router
end
