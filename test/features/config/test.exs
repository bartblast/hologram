import Config

config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
  secret_key_base: "+c4nzKpOujvWTRjsuvgfREOT8nnWvr/ZL0t+CR5AeWkiJQl36INDkV7uAvyGgnBa",
  server: true

# HOLOGRAM_FEATURE_TESTS_HTTPS serves the same app over TLS, where Chrome negotiates
# HTTP/2 - Bandit offers it over TLS by default. Tests touching the SSE stream then run
# against Bandit's other protocol, whose stream lifecycle is unlike HTTP/1.1's. The cert
# is a test-only self-signed pair. Endpoint.url/0 follows the listener, and Wallaby
# follows Endpoint.url/0, so nothing else changes.
if System.get_env("HOLOGRAM_FEATURE_TESTS_HTTPS") do
  config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
    https: [
      certfile: Path.expand("../priv/cert/selfsigned.pem", __DIR__),
      ip: {127, 0, 0, 1},
      keyfile: Path.expand("../priv/cert/selfsigned_key.pem", __DIR__),
      port: 4002
    ]
else
  config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: 4002]
end

config :logger, level: :warning

# Lets a feature test hold the SSE attach open via cookie, so a boot-time command can
# reach the server before the connection exists. Never enabled outside the test env.
config :hologram, :__sse_attach_delay_enabled__, true

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
          # Accepts the self-signed cert of the HTTPS listener above.
          "--ignore-certificate-errors",
          "--no-sandbox",
          "--user-agent=Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36",
          "--window-size=1280,800"
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
  otp_app: :hologram_feature_tests,
  screenshot_dir: "./tmp/screenshots",
  screenshot_on_failure: true
