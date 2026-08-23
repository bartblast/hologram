windows? = match?({:win32, _name}, :os.type())

# A static file whose path holds what the inline asset-manifest script cannot carry raw: a
# quote, a backslash, and - the directory's trailing "<" meeting the file's leading "script>" -
# a closing script tag. Planted here rather than committed, because every one of those
# characters is illegal in a Windows file name, so a repo carrying the file could not be
# checked out there at all. It has to exist before the Hologram app boots, which in the test
# env happens in Hologram.Test.setup/0 below, where the static dir is scanned once. Read by
# test/asset_manifest_test.exs through HologramFeatureTests.AssetManifestPage.
unless windows? do
  hostile_dir =
    Path.join([
      Application.app_dir(:hologram_feature_tests, "priv/static"),
      "hostile",
      ~S|quote"backslash\tag<|
    ])

  File.mkdir_p!(hostile_dir)

  hostile_dir
  |> Path.join("script>.txt")
  |> File.write!("")
end

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

# The file planted above cannot exist on Windows, and neither can the bug it exercises - a
# static path there can never hold any of the characters the manifest escapes. The one test
# that reads it is therefore skipped on Windows permanently, not pending a fix. Same tag as
# the lib suite uses, see test/elixir/test_helper.exs.
exclude_opts = if windows?, do: [:skip_on_windows], else: []

ExUnit.start(exclude: exclude_opts)

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
