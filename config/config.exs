# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

# Framework config
config :hologram,
  default_layout: Hologram.E2E.DefaultLayout,
  pages_path: "#{File.cwd!()}/lib/e2e/pages"

config :hologram,
  ecto_repos: [Demo.Repo]

# Configures the endpoint
config :hologram, DemoWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "yVz5aKrBHZaey4gZeR/oHoTTwxNKd28g4yGjTvZ18kwAAN6AAwf37h33edqpFPtV",
  render_errors: [view: DemoWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Demo.PubSub,
  live_view: [signing_salt: "5wOr/GQo"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
