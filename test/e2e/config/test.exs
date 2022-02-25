import Config

config :hologram_e2e, Hologram.E2EWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: true

config :logger, level: :warn

config :phoenix, :plug_init_mode, :runtime

config :wallaby,
  otp_app: :hologram_e2e,
  driver: Wallaby.Chrome,
  screenshot_dir: "./tmp/screenshots"
