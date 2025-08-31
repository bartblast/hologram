defmodule HologramFeatureTests.Actions.Page8 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Actions.Component11

  route "/actions/8"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, show_component?: false)
  end

  def template do
    ~HOLO"""
    {%if @show_component?}
      <Component11 cid="component_11" />
    {%else}
      Component11 is hidden
    {/if}
    <p>
      <button $click="show_component">Show component</button>
    </p>    
    """
  end

  def action(:show_component, _params, component) do
    put_state(component, show_component?: true)
  end
end
