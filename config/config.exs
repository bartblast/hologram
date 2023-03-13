import Config

config :hologram, debug_transformer: false

import_config "#{config_env()}.exs"
