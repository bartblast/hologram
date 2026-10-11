import Config

config :ash,
  custom_types: [money: AshMoney.Types.Money],
  default_string_length_count: :codepoints,
  known_types: [AshMoney.Types.Money]

config :ex_money, auto_start_exchange_rate_service: false

config :hologram_ecosystem_tests, HologramEcosystemTestsWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: HologramEcosystemTests.PubSub,
  render_errors: [
    formats: [json: HologramEcosystemTestsWeb.ErrorJSON],
    layout: false
  ],
  url: [host: "localhost"]

config :hologram_ecosystem_tests, ash_domains: [HologramEcosystemTests.Ash.Domain]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix,
  json_library: Jason,
  plug_init_mode: :runtime

import_config "#{config_env()}.exs"
