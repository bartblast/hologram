# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# E2E tests
config :hologram,
  app_name: :hologram,
  app_path: "#{File.cwd!()}/e2e",
  default_layout: Hologram.E2E.DefaultLayout,
  router_module: DemoWeb.Router

# Configures the endpoint
config :hologram, HologramWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "/t99BcKoIa8IKka6K9dhpfoRHHYP0fK/FXFNdWO5Wlt+h1wlFeBODgIi8U4XACBE",
  render_errors: [view: HologramWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Hologram.PubSub,
  live_view: [signing_salt: "Wa1Wmntm"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.12.18",
  default: [
    args: ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
