import Config

config :hologram_sync_tests, HologramSyncTestsWeb.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "ECevjiT40ecLkY8U5rI2rEG6lA4fiZudbb9lwF43iutNmTF7NLrnvSIUQRRbiez",
  watchers: []

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
