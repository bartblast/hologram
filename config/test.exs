import Config

config :hologram, Hologram.E2E.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: true

config :logger, level: :warn

config :phoenix, :plug_init_mode, :runtime

config :wallaby,
  driver: Wallaby.Chrome,
  otp_app: :hologram,
  screenshot_dir: "./tmp/screenshots"
