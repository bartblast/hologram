import Config

config :app_1, App1.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "Bom6mFsKxvRC+9VH1tiepyEgWYWWIzRi2TyNk9mqDjCBFC7dGZ1jKgdtzdLxXAVo",
  watchers: []

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
