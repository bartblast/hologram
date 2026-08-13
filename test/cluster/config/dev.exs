import Config

config :hologram_cluster_tests, HologramClusterTestsWeb.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: 4004],
  secret_key_base: "wK5c8mQnJ2vRfTz9BxYhE3aGdN7pLsU4C6jViObM0WqXtZrAeD1kFyHgPnSuIlo0",
  watchers: []

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
