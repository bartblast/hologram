defmodule HologramFeatureTests.Components.TemplateSyntax.Component8 do
  use Hologram.Component

  def init(_props, component) do
    put_state(component, :count, 0)
  end

  def init(_props, component, _server) do
    put_state(component, :count, 0)
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end

  def template do
    ~HOLO"""
    <div id="component_8">
      component_8 count = {@count}
      <button $click="increment" id="component_8_button">Increment</button>
    </div>
    """
  end
end
