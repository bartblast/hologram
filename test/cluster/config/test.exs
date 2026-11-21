import Config

# `server: false` because this config belongs to the ORCHESTRATOR - the node running
# ExUnit, Wallaby and the proxy, which serves no app traffic itself, so its port is never
# bound. Peers get the env copied with `server: true` and a port of their own before the app
# starts there.
config :hologram_cluster_tests, HologramClusterTestsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "wK5c8mQnJ2vRfTz9BxYhE3aGdN7pLsU4C6jViObM0WqXtZrAeD1kFyHgPnSuIlo0",
  server: false

# Every peer of every test connects its own pool - the app declares entities, which
# activates the database everywhere the app boots. A small pool keeps a suite of
# multi-peer tests far below the server's connection limit, and no cluster test issues
# concurrent queries from one node.
config :hologram, :database, pool_size: 2

# Sync's own pool opens connections of its own on every peer too, and no cluster test catches up
# more than one client at once on a node.
config :hologram, :sync, pool_size: 1

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
          "--window-size=1280,800"
        ]
      }
    }
  ],
  driver: Wallaby.Chrome,
  # Fixes occasional HTTPoison timeouts, see: https://github.com/elixir-wallaby/wallaby/issues/365
  hackney_options: [timeout: 60_000, recv_timeout: 60_000],
  max_wait_time: 30_000,
  otp_app: :hologram_cluster_tests,
  screenshot_dir: "./tmp/screenshots",
  screenshot_on_failure: true
