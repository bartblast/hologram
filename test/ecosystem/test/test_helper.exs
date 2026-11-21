Hologram.Test.setup()

# One case at a time on CI, for the same reason as the feature tests app: every test
# drives a real browser, and more than one per runner made the suite flaky.
if System.get_env("GITHUB_ACTIONS") == "true" do
  ExUnit.configure(max_cases: 1)
end

ExUnit.start()

# The endpoint listens on port 0, so the OS gave it a free port, and runs that overlap on one
# machine never share one. Its URL still says port 0, so the port the listener got is put into
# it: the URL is how Wallaby and the tests reach the app.
endpoint = HologramEcosystemTestsWeb.Endpoint
{:ok, {_ip, port}} = endpoint.server_info(:http)

endpoint_config =
  :hologram_ecosystem_tests
  |> Application.fetch_env!(endpoint)
  |> Keyword.update!(:url, &Keyword.put(&1, :port, port))

Application.put_env(:hologram_ecosystem_tests, endpoint, endpoint_config)
endpoint.config_change([{endpoint, endpoint_config}], [])

# Kills the test browsers that ended runs left behind, then starts Wallaby with ChromeDriver's
# log on, in this run's folder of tmp/chromedriver, restarting it when ChromeDriver doesn't get
# ready. CI uploads tmp/chromedriver when a run fails or hangs.
Hologram.Test.BrowserSession.start_wallaby()
Application.put_env(:wallaby, :base_url, endpoint.url())
