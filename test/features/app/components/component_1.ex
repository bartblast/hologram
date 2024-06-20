defmodule HologramFeatureTests.Components.Component1 do
  use Hologram.Component

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <p>
      <button id="component_1_action_1" $click="component_1_action_1"> component_1_action_1 </button>
    </p>        
    <p>
      Component 1 result: <strong id="component_1_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:component_1_action_1, params, component) do
    put_state(component, :result, {"component_1_action_1", params})
  end

  def action(:component_1_action_2, params, component) do
    put_state(component, :result, {"component_1_action_2", params})
  end

  def action(:component_1_action_3, params, component) do
    put_state(component, :result, {"component_1_action_3", params})
  end
end
