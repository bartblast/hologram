import Config

config :hologram_feature_tests, HologramFeatureTestsWeb.Endpoint,
  secret_key_base: "+c4nzKpOujvWTRjsuvgfREOT8nnWvr/ZL0t+CR5AeWkiJQl36INDkV7uAvyGgnBa",
  server: true

# HOLOGRAM_FEATURE_TESTS_HTTPS serves the same app over TLS, where Chrome negotiates
# HTTP/2 - Bandit offers it over TLS by default. Tests touching the SSE stream then run
# against Bandit's other protocol, whose stream lifecycle is unlike HTTP/1.1's.
# Endpoint.url/0 follows the listener, and Wallaby follows Endpoint.url/0, so nothing
# else changes.
#
# The cert is a test-only self-signed pair made with OpenSSL, not `mix phx.gen.cert`:
#
#   openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
#     -subj "/O=Hologram feature tests/CN=localhost" \
#     -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
#     -keyout priv/cert/selfsigned_key.pem -out priv/cert/selfsigned.pem
#
# phx.gen.cert leaves out the NULL parameters of the public key's rsaEncryption algorithm
# identifier, which RFC 3279 requires. OpenSSL and curl accept that, Chrome's BoringSSL
# does not: it rejects the key with a fatal decode error and every page load fails.
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

# Lets a feature test drive the SSE stream's test seams via cookies: hold the attach open,
# so a boot-time command can reach the server before the connection exists, and shorten
# the heartbeat, so a silent stream's reconnect fits the wait budget. Never enabled
# outside the test env.
config :hologram, :__sse_test_seams_enabled__, true

config :wallaby,
  chromedriver: [
    # Optimize for GithHub Actions CI environment, see: https://github.com/elixir-wallaby/wallaby/issues/468#issuecomment-1113520767
    capabilities: %{
      chromeOptions: %{
        args: [
          "--disable-background-timer-throttling",
          "--disable-dev-shm-usage",
          # A fresh profile asks Google for the time at startup, and the reply rebuilds the
          # certificate verifier, which drops every HTTP/2 session with
          # ERR_CERT_VERIFIER_CHANGED. That killed the first page load of a test now and
          # then in the HTTPS job, where Chrome speaks HTTP/2.
          "--disable-features=NetworkTimeServiceQuerying",
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
