import Config

config :hologram_sync_tests, HologramSyncTestsWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: HologramSyncTests.PubSub,
  url: [host: "localhost"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix,
  json_library: Jason,
  plug_init_mode: :runtime

import_config "#{config_env()}.exs"
