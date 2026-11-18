import Config

# The driver runs with `mix run --no-start` and serves nothing itself, so the endpoint is off
# here. The server node gets this env copied with `server: true` (see HologramSyncBenchmark.Peer).
#
# The listen backlog is raised for the reconnect case, which connects every client at once.
# macOS caps it at kern.ipc.somaxconn whatever this asks for.
config :hologram_sync_benchmark, HologramSyncBenchmarkWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  http: [
    ip: {127, 0, 0, 1},
    port: 4110,
    thousand_island_options: [transport_options: [backlog: 4096]]
  ],
  pubsub_server: HologramSyncBenchmark.PubSub,
  secret_key_base: "Qm3vT8xLw2rN6yHc9KpA4dZsF7gJ1uBe5iRoX0aVnMtCqEhWl2YkSjGfUzDb8PoI",
  server: false,
  url: [host: "localhost"]

# Named outright: the default name follows the env, and the server node runs as :test while the
# driver runs as :dev. The pool keeps Hologram's default size, 10, as an app that doesn't set one.
config :hologram, :database, database: "hologram_sync_benchmark"

config :logger, level: :warning

config :phoenix, json_library: Jason
