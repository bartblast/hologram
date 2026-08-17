Hologram.Test.setup()

# One case at a time on CI. Every test drives a real browser, and ExUnit's default
# of one case per scheduler put more of them on a runner than it could carry, which
# made the suite flaky rather than merely slow. The suite is kept fast by splitting
# it across runners instead of within one - see the partition matrix in the
# feature_tests job of .github/workflows/ci.yml - so each runner is left with the
# single-browser load it handles reliably. Off CI the default applies.
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
