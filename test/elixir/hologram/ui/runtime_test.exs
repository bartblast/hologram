defmodule Hologram.UI.RuntimeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Runtime.AssetPathRegistry
  alias Hologram.UI.Runtime

  use_module_stub :asset_path_registry

  setup :set_mox_global

  setup do
    stub_with(AssetPathRegistryMock, AssetPathRegistryStub)
    setup_asset_fixtures(AssetPathRegistryStub.static_dir_path())
    AssetPathRegistry.start_link([])

    [
      context: %{
        {Hologram.Runtime, :client_data_loaded?} => false,
        {Hologram.Runtime, :page_digest} => "102790adb6c3b1956db310be523a7693"
      }
    ]
  end

  test "client_data_loaded? = false", %{context: context} do
    assert render_component(Runtime, %{}, context) == """
           <script>
             
               
                 window.__hologramPageMountData__ = (typeClass) => {
                   const Type = typeClass;
                   
                   return {
                     clientsData: $INJECT_CLIENTS_DATA,
                     pageModule: $INJECT_PAGE_MODULE,
                     pageParams: $INJECT_PAGE_PARAMS
                   };
                 };
               
             
           </script>
           <script async src="/hologram/runtime.js"></script>
           <script async src="/hologram/page-102790adb6c3b1956db310be523a7693.js"></script>\
           """
  end

  test "client_data_loaded? = true", %{context: context} do
    context = Map.put(context, {Hologram.Runtime, :client_data_loaded?}, true)

    assert render_component(Runtime, %{}, context) == """
           <script>
             
           </script>
           <script async src="/hologram/runtime.js"></script>
           <script async src="/hologram/page-102790adb6c3b1956db310be523a7693.js"></script>\
           """
  end
end
