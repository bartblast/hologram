defmodule Hologram.Runtime.ApplicationTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Runtime.Application
  import Hologram.Test.Stubs
  import Mox

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    stub_with(PageModuleResolverMock, PageModuleResolverStub)
    stub_with(AssetManifestCacheMock, AssetManifestCacheStub)
    stub_with(AssetPathRegistryMock, AssetPathRegistryStub)
    stub_with(PageDigestRegistryMock, PageDigestRegistryStub)

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
