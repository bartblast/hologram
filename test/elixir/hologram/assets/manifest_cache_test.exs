defmodule Hologram.Assets.ManifestCacheTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Assets.ManifestCache
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.ManifestCache, as: AssetManifestCache

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry

  setup :set_mox_global

  setup do
    setup_asset_path_registry(AssetPathRegistryStub)
    setup_asset_manifest_cache(AssetManifestCacheStub, false)
  end

  test "get_manifest_js/0" do
    init(nil)

    assert get_manifest_js() == """
           globalThis.hologram.assetManifest = {
           "hologram/runtime.js": "/hologram/runtime-00000000000000000000000000000000.js",
           "hologram/test_file_9.css": "/hologram/test_file_9-99999999999999999999999999999999.css",
           "test_dir_1/test_dir_2/page.js": "/test_dir_1/test_dir_2/page-33333333333333333333333333333333.js",
           "test_dir_1/test_dir_2/test_file_1.css": "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css",
           "test_dir_1/test_dir_2/test_file_2.css": "/test_dir_1/test_dir_2/test_file_2-22222222222222222222222222222222.css",
           "test_dir_3/page.js": "/test_dir_3/page-66666666666666666666666666666666.js",
           "test_dir_3/test_file_10.css": "/test_dir_3/test_file_10.css",
           "test_dir_3/test_file_4.css": "/test_dir_3/test_file_4-44444444444444444444444444444444.css",
           "test_dir_3/test_file_5.css": "/test_dir_3/test_file_5-55555555555555555555555555555555.css"
           };\
           """
  end

  test "init/1" do
    assert init(nil) == {:ok, nil}
    assert :persistent_term.get(AssetManifestCacheStub.persistent_term_key()) == get_manifest_js()
  end

  test "reload/0" do
    AssetManifestCache.start_link([])

    key = AssetManifestCacheStub.persistent_term_key()
    :persistent_term.put(key, :dummy_value)

    reload()

    assert :persistent_term.get(key) == """
           globalThis.hologram.assetManifest = {
           "hologram/runtime.js": "/hologram/runtime-00000000000000000000000000000000.js",
           "hologram/test_file_9.css": "/hologram/test_file_9-99999999999999999999999999999999.css",
           "test_dir_1/test_dir_2/page.js": "/test_dir_1/test_dir_2/page-33333333333333333333333333333333.js",
           "test_dir_1/test_dir_2/test_file_1.css": "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css",
           "test_dir_1/test_dir_2/test_file_2.css": "/test_dir_1/test_dir_2/test_file_2-22222222222222222222222222222222.css",
           "test_dir_3/page.js": "/test_dir_3/page-66666666666666666666666666666666.js",
           "test_dir_3/test_file_10.css": "/test_dir_3/test_file_10.css",
           "test_dir_3/test_file_4.css": "/test_dir_3/test_file_4-44444444444444444444444444444444.css",
           "test_dir_3/test_file_5.css": "/test_dir_3/test_file_5-55555555555555555555555555555555.css"
           };\
           """
  end

  test "start_link/1" do
    assert {:ok, pid} = AssetManifestCache.start_link([])
    assert is_pid(pid)
    assert persistent_term_exists?(AssetManifestCacheStub.persistent_term_key())
  end
end
