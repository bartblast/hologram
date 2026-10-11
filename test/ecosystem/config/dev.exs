import Config

config :hologram_ecosystem_tests, HologramEcosystemTestsWeb.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "Tq8vLz3NcWmR6pYd1KsHfGx0JbEo9AuQ2iVtZ7lCeX4gMnSaD5rPwOyUkIhB8jFq",
  watchers: []

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
