import Config

config :hologram,
  otp_app: :hologram,
  app_path: "#{File.cwd!()}/e2e",
  default_layout: Hologram.E2E.DefaultLayout,
  env: config_env(),
  ignored_namespaces: [
    Hologram.Commons,
    Hologram.Compiler,
    Hologram.Template
  ]

config :hologram, Hologram.E2E.Web.Endpoint,
  pubsub_server: Hologram.E2E.PubSub,
  render_errors: [view: Hologram.E2E.Web.ErrorView, accepts: ~w(html json), layout: false],
  secret_key_base: "/t99BcKoIa8IKka6K9dhpfoRHHYP0fK/FXFNdWO5Wlt+h1wlFeBODgIi8U4XACBE",
  url: [host: "localhost"]

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

import_config "#{config_env()}.exs"

Application.ensure_all_started(:logger)
logger_config = Application.fetch_env!(:logger, :console)
Logger.configure_backend(:console, logger_config)
