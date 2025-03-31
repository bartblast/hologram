import Config

config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+c4nzKpOujvWTRjsuvgfREOT8nnWvr/ZL0t+CR5AeWkiJQl36INDkV7uAvyGgnBa",
  server: true

config :logger, level: :warning

config :wallaby,
  chromedriver: [
    # Optimize for GithHub Actions CI environment, see: https://github.com/elixir-wallaby/wallaby/issues/468#issuecomment-1113520767
    capabilities: %{
      chromeOptions: %{
        args: [
          "--disable-dev-shm-usage",
          "--disable-gpu",
          "--fullscreen",
          "--headless",
          "--no-sandbox",
          "--user-agent=Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36",
          "window-size=1280,800"
        ]
      }
    }
  ],
  driver: Wallaby.Chrome,
  # Fixes occasional HTTPoison timeouts, see: https://github.com/elixir-wallaby/wallaby/issues/365
  hackney_options: [timeout: 60_000, recv_timeout: 60_000],
  max_wait_time: 30_000,
  otp_app: :hologram_feature_tests,
  screenshot_dir: "./tmp/screenshots",
  screenshot_on_failure: true
