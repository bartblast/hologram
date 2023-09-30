defmodule Hologram.Runtime.AssetManifestCacheTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.AssetManifestCache

  alias Hologram.Commons.Reflection
  alias Hologram.Runtime.AssetPathRegistry

  @asset_path_registry_process_name random_atom()
  @static_path "#{Reflection.tmp_path()}/#{__MODULE__}"
  @store_key random_atom()
  @opts [
    asset_path_registry_process_name: @asset_path_registry_process_name,
    store_key: @store_key
  ]

  setup do
    clean_dir(@static_path)
    setup_asset_fixtures(@static_path)

    AssetPathRegistry.start_link(
      process_name: @asset_path_registry_process_name,
      static_path: @static_path,
      store_key: random_atom()
    )

    :ok
  end

  test "init/1" do
    assert init(@opts) == {:ok, @opts}

    assert :persistent_term.get(@store_key) ==
             """
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

  test "start_link/1" do
    assert {:ok, pid} = start_link(@opts)

    assert is_pid(pid)
    assert persistent_term_exists?(@store_key)
  end
end
