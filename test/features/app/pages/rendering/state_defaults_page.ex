defmodule HologramFeatureTests.Rendering.StateDefaultsPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.Rendering.StateDefaultsClientComponent
  alias HologramFeatureTests.Components.Rendering.StateDefaultsComponent

  route "/rendering/state-defaults"

  layout HologramFeatureTests.Components.StateDefaultsLayout

  # No init/3 on purpose: the declared defaults are all the state the page starts with.
  state :greeting, :string, default: "page default"
  state :show_component_2, :boolean, default: false

  def template do
    ~HOLO"""
    <p id="page_greeting">{@greeting}</p>
    <p>
      <button $click="show_component_2">Show component 2</button>
    </p>
    <StateDefaultsComponent cid="component_1" />
    {%if @show_component_2}
      <StateDefaultsClientComponent cid="component_2" />
    {/if}
    """
  end

  # Component 2 only enters the tree once the page is already loaded, so its declared defaults
  # seed its state on the client.
  def action(:show_component_2, _params, component) do
    put_state(component, :show_component_2, true)
  end
end
