import Config

config :hologram,
  debug_encoder: false,
  debug_parser: false,
  debug_transformer: false

config :logger, :default_formatter, metadata: [:crash_reason]

import_config "#{config_env()}.exs"
