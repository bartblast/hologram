defmodule HologramSyncBenchmarkWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hologram_sync_benchmark

  @session_options [
    key: "hologram_sync_benchmark_session",
    same_site: "Lax",
    signing_salt: "Vb7qLx2K",
    store: :cookie
  ]

  plug Plug.Static,
    at: "/",
    from: :hologram_sync_benchmark,
    gzip: false,
    only: ~w(hologram)

  plug Plug.Parsers,
    json_decoder: Phoenix.json_library(),
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"]

  plug Plug.Session, @session_options

  plug Hologram.Router
end
