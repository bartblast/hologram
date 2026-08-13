import Config

# Every app instance in the cluster runs from this same build, so the port comes from an
# env var - the orchestrator assigns each peer its own before starting the app there.
config :hologram_cluster_tests, HologramClusterTestsWeb.Endpoint,
  http: [
    ip: {127, 0, 0, 1},
    port: String.to_integer(System.get_env("HOLOGRAM_CLUSTER_TESTS_PORT") || "4003")
  ],
  secret_key_base: "wK5c8mQnJ2vRfTz9BxYhE3aGdN7pLsU4C6jViObM0WqXtZrAeD1kFyHgPnSuIlo0",
  server: true

config :logger, level: :warning

config :wallaby,
  chromedriver: [
    # Optimize for GithHub Actions CI environment, see: https://github.com/elixir-wallaby/wallaby/issues/468#issuecomment-1113520767
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
  # Fixes occasional HTTPoison timeouts, see: https://github.com/elixir-wallaby/wallaby/issues/365
  hackney_options: [timeout: 60_000, recv_timeout: 60_000],
  max_wait_time: 30_000,
  otp_app: :hologram_cluster_tests,
  screenshot_dir: "./tmp/screenshots",
  screenshot_on_failure: true
