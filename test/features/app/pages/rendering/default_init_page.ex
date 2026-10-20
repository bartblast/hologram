defmodule HologramFeatureTests.Rendering.DefaultInitPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.Rendering.DefaultInitComponent

  route "/rendering/default-init"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :show_component_2, false)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="show_component_2">Show component 2</button>
    </p>
    <DefaultInitComponent cid="component_1" label="first" />
    {%if @show_component_2}
      <DefaultInitComponent cid="component_2" label="second" />
    {/if}
    """
  end

  # Component 2 only enters the tree once the page is already loaded, so it initializes on the
  # client through the default init/2 rather than on the server through the default init/3.
  def action(:show_component_2, _params, component) do
    put_state(component, :show_component_2, true)
  end
end
