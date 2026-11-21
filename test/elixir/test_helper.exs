alias Hologram.Assets.ChunkRegistry
alias Hologram.Assets.ManifestCache, as: AssetManifestCache
alias Hologram.Assets.PageDigestRegistry
alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.DB.QueryCache
alias Hologram.LiveReload
alias Hologram.Reflection
alias Hologram.Router.PageModuleResolver
alias Hologram.Sync.PageTypes, as: SyncPageTypes

# Create tmp dir if it doesn't exist yet.
File.mkdir_p!(Reflection.tmp_dir())

System.put_env(
  "SECRET_KEY_BASE",
  "test_secret_key_base_that_is_long_enough_for_testing_purposes_in_hologram"
)

# Skip tests that don't work reliably on either OS type
exclude_opts =
  case :os.type() do
    {:unix, _name} -> [:skip_on_unix]
    {:win32, _name} -> [:skip_on_windows]
  end

# Make OTP's :cover available (tools app) - the compiler cover tests exercise
# cover-compiled modules, and the reference must resolve at test compile time.
Mix.ensure_application!(:tools)

# The running app reads the project's data model from the module info dump the Hologram compiler
# writes at the end of a compile. Mix compiles this project, not the Hologram compiler, so the
# dump is written here, from the same beams.
build_dir = Reflection.build_dir()

# TODO: Remove once no build from before the Dialyzer PLTs left the priv dir is around (a local
# _build, a CI cache). Mix linked the build dir to that priv dir and leaves the link behind now
# that the dir is gone: a dangling link, under which nothing can be created.
if match?({:ok, _target}, File.read_link(build_dir)) and not File.exists?(build_dir) do
  File.rm!(build_dir)
end

File.mkdir_p!(build_dir)

module_info_plt = Compiler.build_module_info_plt!(PLT.start(), nil)

module_info_plt_dump_path =
  Path.join(build_dir, Reflection.module_info_plt_dump_file_name())

PLT.dump(module_info_plt, module_info_plt_dump_path)
PLT.stop(module_info_plt)

# A running app holds every derived field's definition before anything reads its policies - the
# build puts them, and the query cache at boot. A support fixture whose rule reads a derived set, or
# whose verdicts' keys digest a derived field's definition, has every write, frame and edges index
# read that definition, so each such fixture's are put for the whole run - one added later belongs
# in this list.
Hologram.Test.Helpers.put_derived_definitions([
  Hologram.Test.Fixtures.Entity.Module42,
  Hologram.Test.Fixtures.Policy.Module22,
  Hologram.Test.Fixtures.Policy.Module30,
  Hologram.Test.Fixtures.Policy.Module31,
  Hologram.Test.Fixtures.Policy.Readers.Module15,
  Hologram.Test.Fixtures.Policy.Readers.Module17,
  Hologram.Test.Fixtures.Policy.Readers.Module9
])

# What the command line excludes, read before ExUnit.start/1 replaces the list with the
# suite's own below. Mix merges the two again once this file has run.
excluded_tags = ExUnit.configuration()[:exclude]

ExUnit.start(exclude: exclude_opts)

# A run that excludes the database tests (the modules of DatabaseCase and ScratchDatabaseCase,
# and the tests tagged :database by hand) needs no server. It still needs the mapping and the
# clock, which code that never touches a server reads. Every other run boots the database
# here, before the first test, and the boot sets up both.
if :database in excluded_tags do
  Hologram.DB.put_boot_facts()
else
  # Boot the test database: server connectivity check (fail fast with instructions), then a
  # fresh database of this run's own, which the config is pointed at, so runs that overlap
  # leave each other's tables alone. Positioned after ExUnit.start and before the pool boots -
  # the env guard recognizes the test env by the running ExUnit server.
  Hologram.Test.DatabaseBootstrap.run!()

  # Boot the database gateway for the whole suite with a per-process ownership pool, so that
  # every test process transparently gets its own connection. Positioned after ExUnit.start,
  # because environment detection recognizes the test env by the running ExUnit server.
  {:ok, _database_pid} = Hologram.DB.start_link(pool: DBConnection.Ownership)

  # Create the fixture schema layout from scratch: reconciliation claims the virgin database
  # and converges it to the fixture entity model - the suite is auto-sync's first consumer.
  # Under an explicit checkout: this process lives for the whole run, and a connection the
  # pool handed it implicitly would stay owned until the ownership timeout disconnected it,
  # two minutes in.
  pool_name = Hologram.DB.pool_name()
  :ok = DBConnection.Ownership.ownership_checkout(pool_name, [])

  try do
    Hologram.DB.SchemaReconciler.reconcile(Hologram.DB.reconciliation_context())
  after
    :ok = DBConnection.Ownership.ownership_checkin(pool_name, [])
  end

  # The suite needs a role that can create databases. A test that revokes a catalog grant needs a
  # superuser, so it's left out for a role that isn't one - but never on CI, where leaving it out
  # would mean nothing runs it.
  {:ok, role_session} =
    []
    |> Hologram.DB.Config.connection_opts()
    |> Postgrex.start_link()

  %{rows: [[superuser?]]} =
    Postgrex.query!(
      role_session,
      "SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname = current_user",
      []
    )

  GenServer.stop(role_session)

  cond do
    superuser? ->
      :ok

    System.get_env("CI") ->
      raise "the CI database role has to be a superuser, or the :requires_superuser tests don't run"

    true ->
      ExUnit.configure(exclude: [:requires_superuser | ExUnit.configuration()[:exclude]])
  end
end

Mox.defmock(AssetManifestCacheMock, for: AssetManifestCache)
Application.put_env(:hologram, :asset_manifest_cache_impl, AssetManifestCacheMock)

Mox.defmock(AssetPathRegistryMock, for: AssetPathRegistry)
Application.put_env(:hologram, :asset_path_registry_impl, AssetPathRegistryMock)

Mox.defmock(ChunkRegistryMock, for: ChunkRegistry)
Application.put_env(:hologram, :chunk_registry_impl, ChunkRegistryMock)

Mox.defmock(LiveReloadMock, for: LiveReload)
Application.put_env(:hologram, :live_reload_impl, LiveReloadMock)

Mox.defmock(PageModuleResolverMock, for: PageModuleResolver)
Application.put_env(:hologram, :page_module_resolver_impl, PageModuleResolverMock)

Mox.defmock(PageDigestRegistryMock, for: PageDigestRegistry)
Application.put_env(:hologram, :page_digest_registry_impl, PageDigestRegistryMock)

Mox.defmock(SyncPageTypesMock, for: SyncPageTypes)
Application.put_env(:hologram, :sync_page_types_impl, SyncPageTypesMock)

Mox.defmock(QueryCacheMock, for: QueryCache)
Application.put_env(:hologram, :query_cache_impl, QueryCacheMock)
