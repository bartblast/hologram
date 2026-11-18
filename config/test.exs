import Config

config :hologram,
  debug_encoder: false,
  debug_parser: false,
  debug_transformer: false

# The library suite's database. Clones of the repo testing on one machine set
# HOLOGRAM_TEST_DATABASE (like `hologram_test_5`) so they don't drop each other's schemas - the
# test apps under test/ have databases of their own. Unset, it's the default "hologram_test".
config :hologram, :database, database: System.get_env("HOLOGRAM_TEST_DATABASE", "hologram_test")

config :logger, level: :warning
