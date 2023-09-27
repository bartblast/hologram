defmodule Hologram.UI.RuntimeTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.UI.Runtime

  setup do
    [
      context: %{
        {Hologram.Runtime, :initial_client_data_loaded?} => false,
        {Hologram.Runtime, :page_digest} => "102790adb6c3b1956db310be523a7693"
      }
    ]
  end

  test "initial_client_data_loaded? = false", %{context: context} do
    assert render_component(Runtime, %{}, context) == """
           <script>
             
               window.__hologramRuntimeBootstrapData__ = "...";
             
           </script>
           <script async src="/assets/hologram/page-102790adb6c3b1956db310be523a7693.js"></script>\
           """
  end

  test "initial_client_data_loaded? = true", %{context: context} do
    context = Map.put(context, {Hologram.Runtime, :initial_client_data_loaded?}, true)

    assert render_component(Runtime, %{}, context) == """
           <script>
             
           </script>
           <script async src="/assets/hologram/page-102790adb6c3b1956db310be523a7693.js"></script>\
           """
  end
end
