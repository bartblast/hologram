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

# Boot the feature test database before the app starts: the feature app declares
# entities, which activates the Hologram database - the database itself must exist
# before the pool connects. Each run gets a fresh database of its own, so every run
# converges from scratch and runs that overlap leave each other's tables alone.
# Positioned after ExUnit.start - the env guard recognizes the test env by the running
# ExUnit server.
Hologram.Test.DatabaseBootstrap.run!()

Hologram.Test.setup()

# The endpoint listens on port 0, so the OS gave it a free port, and runs that overlap on one
# machine never share one. Its URL still says port 0, so the port the listener got is put into
# it: the URL is how Wallaby and the tests reach the app.
endpoint = HologramFeatureTestsWeb.Endpoint
scheme = if endpoint.config(:https), do: :https, else: :http
{:ok, {_ip, port}} = endpoint.server_info(scheme)

endpoint_config =
  :hologram_feature_tests
  |> Application.fetch_env!(endpoint)
  |> Keyword.update!(:url, &Keyword.put(&1, :port, port))

Application.put_env(:hologram_feature_tests, endpoint, endpoint_config)
endpoint.config_change([{endpoint, endpoint_config}], [])

# Kills the test browsers that ended runs left behind, then starts Wallaby with ChromeDriver's
# log on, in this run's folder of tmp/chromedriver, restarting it when ChromeDriver doesn't get
# ready. CI uploads tmp/chromedriver when a run fails or hangs.
Hologram.Test.BrowserSession.start_wallaby()
Application.put_env(:wallaby, :base_url, endpoint.url())
