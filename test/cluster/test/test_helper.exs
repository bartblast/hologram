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
# subscriptions are then counted by registry-wide test helpers, so a stray
# browser can satisfy a gate the run's own sessions have not met. Sweeping here
# is safe because this run's own browsers launch later, per test. `pkill` is
# Unix-only, so the `find_executable` guard makes this a no-op (rather than a
# crash) on platforms without it, e.g. Windows.
case System.find_executable("pkill") do
  nil -> :ok
  pkill -> System.cmd(pkill, ["-f", "test-type=webdriver"])
end

# The peers this suite starts are full distributed-Erlang nodes, so the test runner must
# be one as well. epmd has to be up before a node can enable distribution - `-daemon` is
# a no-op when it already is. Longnames against 127.0.0.1 rather than a short name, since
# short names depend on hostname resolution, which differs between dev machines and CI
# runners.
System.cmd("epmd", ["-daemon"])

{:ok, _pid} = Node.start(:"cluster_test@127.0.0.1", :longnames)
Node.set_cookie(:hologram_cluster_tests)

{:ok, _apps} = Application.ensure_all_started(:wallaby)

# The browser talks only to the proxy - never to a peer directly. Which peer serves each
# request is the routing policy's decision, not the browser's.
proxy_port = Application.fetch_env!(:hologram_cluster_tests, :proxy_port)
Application.put_env(:wallaby, :base_url, "http://localhost:#{proxy_port}")
