import Config

config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+c4nzKpOujvWTRjsuvgfREOT8nnWvr/ZL0t+CR5AeWkiJQl36INDkV7uAvyGgnBa",
  server: true

config :logger, level: :warning
