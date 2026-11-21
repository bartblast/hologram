import Config

# The test node serves the app itself: the simulated clients reach it over HTTP and SSE, as a
# browser would. Port 0 has the OS pick a free port, so runs that overlap on one machine never
# share one. The test helper reads the port the listener got, and puts it into the URL
# `Endpoint.url/0` names.
config :hologram_sync_tests, HologramSyncTestsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 0],
  secret_key_base: "aa602d960c615cd84814af51fbbcddd7ff7c8bccc77bcb8f0a1e792f254d5e79",
  server: true

# Small frames and gaps, so the randomized run's fills and catch-ups span several frames and chunks,
# a client can be cut off part way through one, and a client away long enough is sent everything
# again.
config :hologram, :sync, gap_limit: 40, rows_per_frame: 5

config :logger, level: :warning
