import Config

config :app_1, App1.Endpoint,
  pubsub_server: App1.PubSub,
  url: [host: "localhost"]

config :phoenix,
  json_library: Jason,
  plug_init_mode: :runtime

import_config "#{config_env()}.exs"
