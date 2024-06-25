import Config

config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "CzTmNsweZ76CZmFFXPLkK0A5CoDAtKlsRvDTfZmpwLZFqLCzh7QaTJHB49tvxVw7",
  watchers: []

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
