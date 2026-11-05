Hologram.Test.setup()

# One case at a time on CI, for the same reason as the feature tests app: every test
# drives a real browser, and more than one per runner made the suite flaky.
if System.get_env("GITHUB_ACTIONS") == "true" do
  ExUnit.configure(max_cases: 1)
end

ExUnit.start()

# Kill leftover headless test-browser processes before the suite starts. See the same
# block in test/features/test/test_helper.exs for why an orphaned browser matters.
case System.find_executable("pkill") do
  nil -> :ok
  pkill -> System.cmd(pkill, ["-f", "test-type=webdriver"])
end

# Starts Wallaby with ChromeDriver's log on, in tmp/chromedriver, restarting it when
# ChromeDriver doesn't get ready. CI uploads that dir when a run fails or hangs.
Hologram.Test.BrowserSession.start_wallaby()
Application.put_env(:wallaby, :base_url, HologramEcosystemTestsWeb.Endpoint.url())
