# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :reflex,
  ecto_repos: [Reflex.Repo]

# Configures the endpoint
config :reflex, ReflexWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "qCGQzelo6SqwgUaKW+PQXjKfaXampEm7dW8ulz3H+5c4fgMIPsAhsqve9MvU7v4L",
  render_errors: [view: ReflexWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Reflex.PubSub,
  live_view: [signing_salt: "rzNP37VB"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
