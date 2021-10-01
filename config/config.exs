import Config

# E2E tests
config :hologram,
  otp_app: :hologram,
  app_path: "#{File.cwd!()}/e2e",
  default_layout: Hologram.E2E.DefaultLayout,
  router_module: Hologram.E2E.Web.Router

config :hologram, Hologram.E2E.Web.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "/t99BcKoIa8IKka6K9dhpfoRHHYP0fK/FXFNdWO5Wlt+h1wlFeBODgIi8U4XACBE",
  render_errors: [view: Hologram.E2E.Web.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Hologram.E2E.PubSub

config :esbuild,
  version: "0.12.18",
  hologram: [
    args:
      ~w(js/hologram.js --bundle --target=es2016 --outfile=../priv/static/hologram/runtime.js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
