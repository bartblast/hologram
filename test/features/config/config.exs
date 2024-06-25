import Config

config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
  pubsub_server: HologramFeatureTests.PubSub,
  render_errors: [
    formats: [json: HologramFeatureTestsWeb.ErrorJSON],
    layout: false
  ],
  url: [host: "localhost"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix,
  json_library: Jason,
  plug_init_mode: :runtime

import_config "#{config_env()}.exs"
