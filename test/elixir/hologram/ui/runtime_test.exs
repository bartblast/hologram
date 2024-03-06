defmodule Hologram.UI.RuntimeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.ManifestCache, as: AssetManifestCache
  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.UI.Runtime

  use_module_stub :asset_manifest_cache
  use_module_stub :asset_path_registry

  setup :set_mox_global

  setup do
    stub_with(AssetManifestCacheMock, AssetManifestCacheStub)
    stub_with(AssetPathRegistryMock, AssetPathRegistryStub)

    setup_asset_fixtures(AssetPathRegistryStub.static_dir_path())
    AssetPathRegistry.start_link([])
    AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

    AssetManifestCache.start_link([])

    [
      context: %{
        {Hologram.Runtime, :initial_page?} => false,
        {Hologram.Runtime, :page_digest} => "102790adb6c3b1956db310be523a7693",
        {Hologram.Runtime, :page_mounted?} => false
      }
    ]
  end

  test "initial_page? prop = false", %{context: context} do
    markup = render_component(Runtime, %{}, context)
    refute String.contains?(markup, "window.__hologramAssetManifest__")
  end

  test "initial_page? prop = true", %{context: context} do
    context = Map.put(context, {Hologram.Runtime, :initial_page?}, true)
    markup = render_component(Runtime, %{}, context)

    assert String.contains?(markup, "window.__hologramAssetManifest__")
  end

  test "page_mounted? prop = false", %{context: context} do
    markup = render_component(Runtime, %{}, context)
    assert String.contains?(markup, "window.__hologramPageMountData__")
  end

  test "page_mounted? prop = true", %{context: context} do
    context = Map.put(context, {Hologram.Runtime, :page_mounted?}, true)
    markup = render_component(Runtime, %{}, context)

    refute String.contains?(markup, "window.__hologramPageMountData__")
  end

  test "page_digest prop", %{context: context} do
    markup = render_component(Runtime, %{}, context)

    assert String.contains?(
             markup,
             ~s'<script async src="/hologram/page-102790adb6c3b1956db310be523a7693.js">'
           )
  end
end
