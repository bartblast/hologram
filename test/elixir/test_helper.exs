alias Hologram.Assets.ManifestCache, as: AssetManifestCache
alias Hologram.Assets.PageDigestRegistry
alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
alias Hologram.Database.Config, as: DatabaseConfig
alias Hologram.LiveReload
alias Hologram.Reflection
alias Hologram.Router.PageModuleResolver

# Create tmp dir if it doesn't exist yet.
File.mkdir_p!(Reflection.tmp_dir())

System.put_env(
  "SECRET_KEY_BASE",
  "test_secret_key_base_that_is_long_enough_for_testing_purposes_in_hologram"
)

# Postgres is a hard requirement of the test suite - fail fast with instructions when the
# server is unreachable. The check targets the maintenance database, so that it works even
# before the test database exists.
# TODO: fold the SELECT 1 probe into the fixture DDL bootstrap once it exists - its
# maintenance-database connection becomes the connectivity check and this message becomes
# its error boundary, removing the separate round trip.
database_opts =
  :hologram
  |> Application.get_env(:database, [])
  |> DatabaseConfig.resolve!(:test)

{:ok, connection_check_pid} =
  Postgrex.start_link(
    database: "postgres",
    hostname: database_opts[:host],
    password: database_opts[:password],
    port: database_opts[:port],
    username: database_opts[:user]
  )

case Postgrex.query(connection_check_pid, "SELECT 1", []) do
  {:ok, _result} ->
    GenServer.stop(connection_check_pid)

  {:error, _reason} ->
    IO.puts(:stderr, """

    Postgres is required to run the Hologram test suite, but no server is reachable at \
    #{database_opts[:host]}:#{database_opts[:port]} (user "#{database_opts[:user]}").

    Start a local Postgres server, e.g.:
      * macOS (Homebrew): brew services start postgresql
      * Linux (systemd): sudo systemctl start postgresql
      * Docker: docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres

    Override the connection settings with config :hologram, :database in config/test.exs.
    """)

    System.halt(1)
end

# Skip tests that don't work reliably on either OS type
exclude_opts =
  case :os.type() do
    {:unix, _name} -> [:skip_on_unix]
    {:win32, _name} -> [:skip_on_windows]
  end

ExUnit.start(exclude: exclude_opts)

Mox.defmock(AssetManifestCacheMock, for: AssetManifestCache)
Application.put_env(:hologram, :asset_manifest_cache_impl, AssetManifestCacheMock)

Mox.defmock(AssetPathRegistryMock, for: AssetPathRegistry)
Application.put_env(:hologram, :asset_path_registry_impl, AssetPathRegistryMock)

Mox.defmock(LiveReloadMock, for: LiveReload)
Application.put_env(:hologram, :live_reload_impl, LiveReloadMock)

Mox.defmock(PageModuleResolverMock, for: PageModuleResolver)
Application.put_env(:hologram, :page_module_resolver_impl, PageModuleResolverMock)

Mox.defmock(PageDigestRegistryMock, for: PageDigestRegistry)
Application.put_env(:hologram, :page_digest_registry_impl, PageDigestRegistryMock)
