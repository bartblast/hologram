defmodule Hologram.UI.RuntimeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Assets.PathRegistry, as: AssetPathRegistry
  alias Hologram.Server
  alias Hologram.Template.Renderer
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

  # The parts the component can render, each named by a string only that part contains. The fill
  # markers print as nothing, so they are found in the rendered tree instead.
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
    refute String.contains?(markup, @runtime_path)
    refute String.contains?(markup, @page_bundle_path)

    assert fill_names(context) == []
  end

  test "initial page, page not mounted", %{context: context} do
    context = Map.put(context, {Hologram.Runtime, :initial_page?}, true)
    markup = render_component(Runtime, %{}, context)

    assert String.contains?(markup, @shell)
    assert String.contains?(markup, @runtime_path)
    assert String.contains?(markup, @page_bundle_path)

    assert fill_names(context) == ["boot_data", "chunk_script_tags"]
  end

  test "not initial page, page mounted", %{context: initial_context} do
    context =
      initial_context
      |> Map.delete({Hologram.Runtime, :csp_nonce})
      |> Map.put({Hologram.Runtime, :page_mounted?}, true)

    markup = render_component(Runtime, %{}, context)

    refute String.contains?(markup, @shell)
    refute String.contains?(markup, @runtime_path)
    refute String.contains?(markup, @page_bundle_path)

    assert fill_names(context) == []
  end

  # This is the navigation case. The mount data reaches the client as its own payload fields, so
  # the block that would carry it is not rendered - only the page bundle is, and the client drops
  # that one itself.
  test "not initial page, page not mounted", %{context: initial_context} do
    context = Map.delete(initial_context, {Hologram.Runtime, :csp_nonce})
    markup = render_component(Runtime, %{}, context)

    refute String.contains?(markup, @shell)
    refute String.contains?(markup, @runtime_path)
    assert String.contains?(markup, @page_bundle_path)

    assert fill_names(context) == []
  end

  # Under a policy the shell runs only because it carries the nonce, so it holds nothing built from
  # app data: the values the boot reads travel in the boot data block, which the browser never runs.
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

  # A page sent without a policy has no nonce, so the shell names none.
  test "shell, without a CSP nonce", %{context: initial_context} do
    context =
      initial_context
      |> Map.delete({Hologram.Runtime, :csp_nonce})
      |> Map.put({Hologram.Runtime, :initial_page?}, true)

    markup = render_component(Runtime, %{}, context)

    [shell] = Regex.run(~r'<script>.*?</script>'s, markup)

    assert normalize_newlines(shell) ==
             normalize_newlines("""
             <script>
                 globalThis.Hologram ??= {};
                 globalThis.Hologram._pendingJsInteropActions = [];
                 

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

  # The names of the fill markers the component renders, in order.
  defp fill_names(context) do
    node = {:component, Runtime, [], []}

    {tree, _component_registry, _server_struct} =
      Renderer.render_tree(node, %Renderer.Env{context: context}, %Server{})

    tree
    |> List.wrap()
    |> List.flatten()
    |> Enum.flat_map(fn
      {:element, "hologram-fill", attributes, _children} ->
        for {"name", [text: name]} <- attributes, do: name

      _node ->
        []
    end)
  end
end
