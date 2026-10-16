defmodule HologramMinimalTestsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hologram_minimal_tests

  @session_options [
    key: "hologram_minimal_tests_session",
    same_site: "Lax",
    signing_salt: "imZJB8c7",
    store: :cookie
  ]

  plug Plug.Static,
    at: "/",
    from: :hologram_minimal_tests,
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
