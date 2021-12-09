import Config

config :hologram, Hologram.E2E.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  debug_errors: true,
  code_reloader: false,
  check_origin: false,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:hologram, ~w(--sourcemap=inline --watch)]}
  ]
  
config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime
