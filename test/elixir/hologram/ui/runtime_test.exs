defmodule Hologram.UI.RuntimeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.UI.Runtime

  use_module_stub :asset_path_registry

  setup :set_mox_global

  setup do
    setup_asset_path_registry(AssetPathRegistryStub)
    AssetPathRegistry.register("hologram/runtime.js", "/hologram/runtime-1234567890abcdef.js")

    [
      context: %{
        {Hologram.Runtime, :csp_nonce} => "test-csp-nonce-67890",
        {Hologram.Runtime, :initial_page?} => false,
        {Hologram.Runtime, :page_digest} => "102790adb6c3b1956db310be523a7693",
        {Hologram.Runtime, :page_module} => MyPage,
        {Hologram.Runtime, :page_mounted?} => false
      }
    ]
  end

  # The parts the component can render, each named by a string only that part contains.
  @boot_data_token "$BOOT_DATA_PLACEHOLDER"
  @chunk_tags_token "$CHUNK_SCRIPT_TAGS_PLACEHOLDER"
  @page_bundle_path "hologram/page"
  @runtime_path "hologram/runtime"
  @shell "globalThis.Hologram._pendingJsInteropActions"

  test "initial page, page mounted", %{context: context} do
    context =
      context
      |> Map.put({Hologram.Runtime, :initial_page?}, true)
      |> Map.put({Hologram.Runtime, :page_mounted?}, true)

    markup = render_component(Runtime, %{}, context)

    refute String.contains?(markup, @shell)
    refute String.contains?(markup, @boot_data_token)
    refute String.contains?(markup, @runtime_path)
    refute String.contains?(markup, @chunk_tags_token)
    refute String.contains?(markup, @page_bundle_path)
  end

  test "initial page, page not mounted", %{context: context} do
    context = Map.put(context, {Hologram.Runtime, :initial_page?}, true)
    markup = render_component(Runtime, %{}, context)

    assert String.contains?(markup, @shell)
    assert String.contains?(markup, @boot_data_token)
    assert String.contains?(markup, @runtime_path)
    assert String.contains?(markup, @chunk_tags_token)
    assert String.contains?(markup, @page_bundle_path)
  end

  test "not initial page, page mounted", %{context: initial_context} do
    context =
      initial_context
      |> Map.delete({Hologram.Runtime, :csp_nonce})
      |> Map.put({Hologram.Runtime, :page_mounted?}, true)

    markup = render_component(Runtime, %{}, context)

    refute String.contains?(markup, @shell)
    refute String.contains?(markup, @boot_data_token)
    refute String.contains?(markup, @runtime_path)
    refute String.contains?(markup, @chunk_tags_token)
    refute String.contains?(markup, @page_bundle_path)
  end

  # This is the navigation case. The mount data reaches the client as its own payload fields, so
  # the block that would carry it is not rendered - only the page bundle is, and the client drops
  # that one itself.
  test "not initial page, page not mounted", %{context: initial_context} do
    context = Map.delete(initial_context, {Hologram.Runtime, :csp_nonce})
    markup = render_component(Runtime, %{}, context)

    refute String.contains?(markup, @shell)
    refute String.contains?(markup, @boot_data_token)
    refute String.contains?(markup, @runtime_path)
    refute String.contains?(markup, @chunk_tags_token)
    assert String.contains?(markup, @page_bundle_path)
  end

  # The shell runs only because it carries the nonce, so it holds nothing built from app data: the
  # values the boot reads travel in the boot data block, which the browser never runs.
  test "shell", %{context: initial_context} do
    context = Map.put(initial_context, {Hologram.Runtime, :initial_page?}, true)
    markup = render_component(Runtime, %{}, context)

    [shell] = Regex.run(~r'<script>.*?</script>'s, markup)

    assert normalize_newlines(shell) ==
             normalize_newlines("""
             <script>
                 globalThis.Hologram ??= {};
                 globalThis.Hologram._pendingJsInteropActions = [];
                 globalThis.Hologram.cspNonce = "test-csp-nonce-67890";

                 globalThis.Hologram.dispatchAction = function(actionName, target, params) {
                   globalThis.Hologram._pendingJsInteropActions.push([actionName, target, params]);
                 }
               </script>\
             """)
  end

  test "page bundle script", %{context: context} do
    markup = render_component(Runtime, %{}, context)

    assert String.contains?(
             markup,
             ~s'<script async src="/hologram/page-MyPage-102790adb6c3b1956db310be523a7693.js">'
           )
  end
end
