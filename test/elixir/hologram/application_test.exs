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
    setup_asset_path_registry(AssetPathRegistryStub, false)
    setup_asset_manifest_cache(AssetManifestCacheStub, false)

    setup_page_digest_registry(PageDigestRegistryStub, false)

    setup_page_module_resolver(PageModuleResolverStub, false)
  end

  test "start/2" do
    assert {:ok, pid} = start(:my_app, :temporary)
    assert is_pid(pid)
  end
end
