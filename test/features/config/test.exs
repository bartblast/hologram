import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+c4nzKpOujvWTRjsuvgfREOT8nnWvr/ZL0t+CR5AeWkiJQl36INDkV7uAvyGgnBa",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
