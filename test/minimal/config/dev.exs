import Config

config :hologram_minimal_tests, HologramMinimalTestsWeb.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "ehfW6ulWuOoQDMyx0iUokVp0f0EOc7tYkxQe0RVDz5ylSVFImW78XgyACkNMdAsM",
  watchers: []

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
