defmodule HologramFeatureTests.Security.Page4 do
  use Hologram.Page

  route "/security/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <div id="my_div" class="c{" < "}d">a{" & "}b</div>
    <script id="my_script">window.myVar = `1{" < "}2`;</script>
    """
  end
end
