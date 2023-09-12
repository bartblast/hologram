defmodule Hologram.UI.RuntimeTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.UI.Runtime

  test "output" do
    context = %{
      {Hologram.Runtime, :initial_client_data} => "PLACEHOLDER"
    }

    assert render_component(Runtime, %{}, context) == """
           <script>
             window.__hologram_runtime_initial_client_data__ = "PLACEHOLDER";
           </script>\
           """
  end
end
