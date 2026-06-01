import Config

config :hologram,
  debug_encoder: false,
  debug_parser: false,
  debug_transformer: false

import_config "#{config_env()}.exs"
