# Boot the feature test database before the app starts: the feature app declares
# entities, which activates the Hologram database - the database itself must exist
# before the pool connects, and the schema drop makes every run converge from scratch.
Hologram.Test.DatabaseBootstrap.run!()

Hologram.Test.setup()

if System.get_env("GITHUB_ACTIONS") == "true" do
  ExUnit.configure(max_cases: 1)
end

ExUnit.start()

# Kill leftover headless test-browser processes before the suite starts.
# chromedriver launches Chrome with the `--test-type=webdriver` flag, so this
# matches only browsers spawned by Wallaby - never a real browser. A
# hard-interrupted run (the BEAM killed before sessions are torn down) can
# orphan such a browser; it then keeps reconnecting its SSE EventSource to every
# subsequent test server and re-registers in the SubscriptionRegistry. Its
# subscriptions are then counted by `wait_for_subscription/5`, which tallies
# across every registered connection, so a stray browser can satisfy a gate the
# run's own sessions have not met. Sweeping here is safe because this run's own
# browsers launch later, per test. `pkill` is Unix-only, so the
# `find_executable` guard makes this a no-op (rather than a crash) on platforms
# without it, e.g. Windows.
case System.find_executable("pkill") do
  nil -> :ok
  pkill -> System.cmd(pkill, ["-f", "test-type=webdriver"])
end

{:ok, _apps} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, HologramFeatureTestsWeb.Endpoint.url())
