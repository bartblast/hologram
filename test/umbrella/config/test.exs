import Config

config :app_1, App1.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "cGXbx/UMm3qsyR8HYYVwO+/SWp1HAYxhFYHO/ugY6VaRenmQs4dCUoSzdxfMEMeS",
  server: true

config :logger, level: :warning

config :wallaby,
  chromedriver: [
    # Optimize for GitHub Actions CI environment
    capabilities: %{
      chromeOptions: %{
        args: [
          "--disable-background-timer-throttling",
          "--disable-dev-shm-usage",
          "--disable-gpu",
          "--fullscreen",
          "--headless",
          "--no-sandbox",
          "--user-agent=Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36",
          "window-size=1280,800"
        ]
      }
    },
    # Increase readiness timeout to prevent chromedriver startup timeouts (default is 10_000 ms)
    readiness_timeout: 60_000
  ],
  driver: Wallaby.Chrome,
  # Fixes occasional HTTPoison timeouts
  hackney_options: [timeout: 60_000, recv_timeout: 60_000],
  max_wait_time: 30_000,
  otp_app: :app_1,
  screenshot_dir: "./tmp/screenshots",
  screenshot_on_failure: true
