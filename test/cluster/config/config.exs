import Config

config :hologram_cluster_tests, HologramClusterTestsWeb.Endpoint,
  pubsub_server: HologramClusterTests.PubSub,
  render_errors: [
    formats: [json: HologramClusterTestsWeb.ErrorJSON],
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
