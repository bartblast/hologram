defmodule HologramFeatureTests.Components.Operations.Component1 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  prop :prop_1, :atom, from_context: :my_context_key

  def init(_props, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button id="layout_action_3" $click={action: :layout_action_3, target: "layout", params: %{a: 1, b: 2}}> layout_action_3 </button>
      <button id="page_action_7" $click={action: :page_action_7, target: "page", params: %{a: 1, b: 2}}> page_action_7 </button>
      <button id="component_1_action_1" $click="component_1_action_1"> component_1_action_1 </button>
    </p>        
    <p>
      Component 1 result: <strong id="component_1_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      Component 1 prop_1: <strong id="component_1_prop_1"><code>{inspect(@prop_1)}</code></strong>
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
