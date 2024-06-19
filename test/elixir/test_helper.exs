alias Hologram.Assets.ManifestCache, as: AssetManifestCache
alias Hologram.Assets.PageDigestRegistry
alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
alias Hologram.Reflection
alias Hologram.Router.PageModuleResolver

# Create tmp dir if it doesn't exist yet.
File.mkdir_p!(Reflection.tmp_dir())

ExUnit.start()

Mox.defmock(AssetManifestCacheMock, for: AssetManifestCache)
Application.put_env(:hologram, :asset_manifest_cache_impl, AssetManifestCacheMock)

Mox.defmock(AssetPathRegistryMock, for: AssetPathRegistry)
Application.put_env(:hologram, :asset_path_registry_impl, AssetPathRegistryMock)

Mox.defmock(PageModuleResolverMock, for: PageModuleResolver)
Application.put_env(:hologram, :page_module_resolver_impl, PageModuleResolverMock)

Mox.defmock(PageDigestRegistryMock, for: PageDigestRegistry)
Application.put_env(:hologram, :page_digest_registry_impl, PageDigestRegistryMock)
