import Config

config :hologram, debug_tag_assembler: false
config :hologram, debug_transformer: false

import_config "#{config_env()}.exs"
