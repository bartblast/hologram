defmodule HologramFeatureTests.Components.Actions.Component20 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_props, component) do
    component
    |> put_state(execution_count: 0, result: nil)
    |> put_action(:component_20_action_a)
  end

  def action(:component_20_action_a, _params, component) do
    put_state(component,
      execution_count: component.state.execution_count + 1,
      result: {:component_20_action_a, component.state.execution_count + 1}
    )
  end

  def action(:component_20_action_b, _params, component) do
    put_state(component, :result, {:component_20_action_b, component.state.execution_count})
  end

  def template do
    ~HOLO"""
    <p>
      Component 20 result: <strong id="component_20_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="component_20_action_b">Run Component 20 Action B</button>
    </p>
    """
  end
end
