import Config

# No test here drives a browser, so the endpoint serves nothing.
config :hologram_minimal_tests, HologramMinimalTestsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "fP2dHVlcHNN6br17WX3uDjAmdt4Bw99P6eEdiwPL1qPtVjRiWhpWPqD4A0WEoZ4Q",
  server: false

config :logger, level: :warning
