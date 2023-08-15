import Config

config :hologram,
  debug_encoder: false,
  debug_parser: false,
  debug_transformer: false,
  env: config_env()

import_config "#{config_env()}.exs"
