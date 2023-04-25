import Config

config :hologram, debug_parser: false
config :hologram, debug_transformer: false

import_config "#{config_env()}.exs"
