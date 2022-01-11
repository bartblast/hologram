import Config

config :hologram, Hologram.E2E.Web.Endpoint,
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:hologram, ~w(--sourcemap=inline --watch)]}
  ]

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime
