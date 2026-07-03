import Config

config :app_1, App1.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "cGXbx/UMm3qsyR8HYYVwO+/SWp1HAYxhFYHO/ugY6VaRenmQs4dCUoSzdxfMEMeS",
  server: true

config :logger, level: :warning
