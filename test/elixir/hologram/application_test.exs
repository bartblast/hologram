defmodule Hologram.ApplicationTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Application
  import Hologram.Test.Stubs
  import Mox

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry
  use_module_stub :page_digest_registry
  use_module_stub :page_module_resolver

  setup :set_mox_global

  setup do
    stub_with(AssetPathRegistryMock, AssetPathRegistryStub)
    stub_with(PageModuleResolverMock, PageModuleResolverStub)

    setup_asset_fixtures(AssetPathRegistryStub.static_dir())

    setup_asset_manifest_cache(AssetManifestCacheStub, false)
    setup_page_digest_registry(PageDigestRegistryStub, false)
  end

  test "start/2" do
    assert {:ok, pid} = start(:my_app, :temporary)
    assert is_pid(pid)
  end
end
