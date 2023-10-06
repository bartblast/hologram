defmodule Hologram.Runtime.AssetManifestCacheTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Runtime.AssetManifestCache
  import Mox

  alias Hologram.Commons.Reflection
  alias Hologram.Runtime.AssetManifestCache
  alias Hologram.Runtime.AssetPathRegistry

  defmodule AssetManifestCacheStub do
    @behaviour AssetManifestCache

    def persistent_term_key, do: __MODULE__
  end

  defmodule AssetPathRegistryStub do
    @behaviour AssetPathRegistry

    def static_dir_path, do: "#{Reflection.tmp_path()}/#{__MODULE__}"

    def ets_table_name, do: __MODULE__

    def process_name, do: __MODULE__
  end

  setup :set_mox_global

  setup do
    stub_with(AssetManifestCache.Mock, AssetManifestCacheStub)
    stub_with(AssetPathRegistry.Mock, AssetPathRegistryStub)

    clean_dir(AssetPathRegistryStub.static_dir_path())
    setup_asset_fixtures(AssetPathRegistryStub.static_dir_path())
    AssetPathRegistry.start_link([])

    :ok
  end

  test "get_manifest_js/0" do
    init(nil)

    assert get_manifest_js() == """
           window.__hologramAssetManifest__ = {
           "/hologram/test_file_9.css": "/hologram/test_file_9-99999999999999999999999999999999.css",
           "/test_dir_1/test_dir_2/page.js": "/test_dir_1/test_dir_2/page-33333333333333333333333333333333.js",
           "/test_dir_1/test_dir_2/test_file_1.css": "/test_dir_1/test_dir_2/test_file_1-11111111111111111111111111111111.css",
           "/test_dir_1/test_dir_2/test_file_2.css": "/test_dir_1/test_dir_2/test_file_2-22222222222222222222222222222222.css",
           "/test_dir_3/page.js": "/test_dir_3/page-66666666666666666666666666666666.js",
           "/test_dir_3/test_file_4.css": "/test_dir_3/test_file_4-44444444444444444444444444444444.css",
           "/test_dir_3/test_file_5.css": "/test_dir_3/test_file_5-55555555555555555555555555555555.css"
           };\
           """
  end

  test "init/1" do
    assert init(nil) == {:ok, nil}
    assert :persistent_term.get(AssetManifestCacheStub.persistent_term_key()) == get_manifest_js()
  end

  test "start_link/1" do
    assert {:ok, pid} = AssetManifestCache.start_link([])
    assert is_pid(pid)
    assert persistent_term_exists?(AssetManifestCacheStub.persistent_term_key())
  end
end
