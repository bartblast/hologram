import Config

config :hologram,
  debug_encoder: false,
  debug_parser: false,
  debug_transformer: false

# Sessions in tests read in the test's own sandbox transaction, which a pool of sync's own would
# read past.
config :hologram, :sync, pool_size: 0

config :logger, level: :warning
