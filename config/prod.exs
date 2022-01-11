import Config

config :hologram, Hologram.E2E.Web.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  url: [host: "example.com", port: 80]

config :logger, level: :info
