Hologram.Test.setup()

if System.get_env("GITHUB_ACTIONS") == "true" do
  ExUnit.configure(max_cases: 1)
end

ExUnit.start()

# Kill leftover headless test-browser processes before the suite starts.
# chromedriver launches Chrome with the `--test-type=webdriver` flag, so this
# matches only browsers spawned by Wallaby - never a real browser. A
# hard-interrupted run (the BEAM killed before sessions are torn down) can
# orphan such a browser, which then keeps reconnecting to every subsequent
# test server. `pkill` is Unix-only, so the `find_executable` guard makes this
# a no-op (rather than a crash) on platforms without it, e.g. Windows.
case System.find_executable("pkill") do
  nil -> :ok
  pkill -> System.cmd(pkill, ["-f", "test-type=webdriver"])
end

{:ok, _apps} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, App1.Endpoint.url())
