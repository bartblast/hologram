import Config

config :hologram_e2e,
  namespace: HologramE2E

config :hologram_e2e, HologramE2EWeb.Endpoint,
  pubsub_server: HologramE2E.PubSub,
  render_errors: [view: HologramE2EWeb.ErrorView, accepts: ~w(json), layout: false],
  secret_key_base: "/t99BcKoIa8IKka6K9dhpfoRHHYP0fK/FXFNdWO5Wlt+h1wlFeBODgIi8U4XACBE",
  url: [host: "localhost"]

config :hologram,
  otp_app: :hologram_e2e,
  default_layout: HologramE2E.DefaultLayout,
  endpoint: HologramE2EWeb.Endpoint,
  env: config_env()

config :esbuild,
  version: "0.14.0",
  hologram: [
    args:
      ~w(../deps/hologram/assets/js/hologram.js --bundle --target=es2016 --outfile=../priv/static/hologram/runtime.js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"

Application.ensure_all_started(:logger)
logger_config = Application.fetch_env!(:logger, :console)
Logger.configure_backend(:console, logger_config)
