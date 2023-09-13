defmodule Hologram.UI.RuntimeTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.UI.Runtime

  test "initial_client_data_loaded? = false" do
    context = %{
      {Hologram.Runtime, :initial_client_data_loaded?} => false
    }

    assert render_component(Runtime, %{}, context) == """
           <script>
             
               window.__hologram_runtime_initial_client_data__ = \"...\";
             
           </script>\
           """
  end

  test "initial_client_data_loaded? = true" do
    context = %{
      {Hologram.Runtime, :initial_client_data_loaded?} => true
    }

    assert render_component(Runtime, %{}, context) == """
           <script>
             
           </script>\
           """
  end
end
