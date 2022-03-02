import Config

config :hologram,
  otp_app: :hologram,
  default_layout: HologramE2E.DefaultLayout,
  env: config_env(),
  ignored_namespaces: [
    Hologram.Commons,
    Hologram.Compiler,
    Hologram.Template
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"

Application.ensure_all_started(:logger)
logger_config = Application.fetch_env!(:logger, :console)
Logger.configure_backend(:console, logger_config)
