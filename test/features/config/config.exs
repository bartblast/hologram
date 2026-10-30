import Config

config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: HologramFeatureTests.PubSub,
  render_errors: [
    formats: [json: HologramFeatureTestsWeb.ErrorJSON],
    layout: false
  ],
  url: [host: "localhost"]

# The whole suite runs under Hologram's policy with Trusted Types enforced, so a script sink the
# runtime writes a plain string to fails whatever test reaches it. The img_src override exercises
# the merge with the defaults, and "default" lets a test create the default policy it needs.
config :hologram,
  content_security_policy: [
    img_src: [:self, "data:"],
    require_trusted_types_for: [:script],
    trusted_types: ["default"]
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix,
  json_library: Jason,
  plug_init_mode: :runtime

import_config "#{config_env()}.exs"
