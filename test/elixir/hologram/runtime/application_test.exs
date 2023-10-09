defmodule Hologram.Runtime.ApplicationTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Runtime.Application
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Router.PageModuleResolver
  alias Hologram.Runtime.AssetManifestCache
  alias Hologram.Runtime.AssetPathRegistry
  alias Hologram.Runtime.PageDigestRegistry

  defmodule AssetManifestCacheStub do
    @behaviour AssetManifestCache

    def persistent_term_key, do: __MODULE__
  end

  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    stub_with(PageModuleResolver.Mock, PageModuleResolverStub)
    stub_with(AssetManifestCache.Mock, AssetManifestCacheStub)
    stub_with(AssetPathRegistry.Mock, AssetPathRegistryStub)
    stub_with(PageDigestRegistry.Mock, PageDigestRegistryStub)

    clean_dir(AssetPathRegistryStub.static_dir_path())
    setup_asset_fixtures(AssetPathRegistryStub.static_dir_path())

    setup_page_digest_registry_dump(PageDigestRegistryStub)

    :ok
  end

  test "start/2" do
    assert {:ok, pid} = start(:my_app, :temporary)
    assert is_pid(pid)
  end
end
