alias Hologram.Assets.ManifestCache, as: AssetManifestCache
alias Hologram.Assets.PageDigestRegistry
alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
alias Hologram.LiveReload
alias Hologram.Reflection
alias Hologram.Router.PageModuleResolver

# Create tmp dir if it doesn't exist yet.
File.mkdir_p!(Reflection.tmp_dir())

System.put_env(
  "SECRET_KEY_BASE",
  "test_secret_key_base_that_is_long_enough_for_testing_purposes_in_hologram"
)

# Boot the test database: server connectivity check (fail fast with instructions), database
# creation when absent, Hologram schema drop (the suite starts virgin).
Hologram.Test.DatabaseBootstrap.run!()

# Skip tests that don't work reliably on either OS type
exclude_opts =
  case :os.type() do
    {:unix, _name} -> [:skip_on_unix]
    {:win32, _name} -> [:skip_on_windows]
  end

ExUnit.start(exclude: exclude_opts)

# Boot the database gateway for the whole suite with a per-process ownership pool, so that
# every test process transparently gets its own connection. Positioned after ExUnit.start,
# because environment detection recognizes the test env by the running ExUnit server.
{:ok, _database_pid} = Hologram.Database.start_link(pool: DBConnection.Ownership)

# Create the fixture schema layout from scratch: reconciliation claims the virgin database
# and converges it to the fixture entity model - the suite is auto-sync's first consumer.
Hologram.Database.SchemaReconciler.reconcile(Hologram.Database.reconciliation_context())

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
