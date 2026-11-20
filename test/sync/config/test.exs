import Config

# The test node serves the app itself: the simulated clients reach it over HTTP and SSE, as a
# browser would. 4006 is free of the other test apps' ports (features 4002, cluster 4003 to 4005
# and 4010 up).
config :hologram_sync_tests, HologramSyncTestsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4006],
  secret_key_base: "aa602d960c615cd84814af51fbbcddd7ff7c8bccc77bcb8f0a1e792f254d5e79",
  server: true

config :logger, level: :warning
