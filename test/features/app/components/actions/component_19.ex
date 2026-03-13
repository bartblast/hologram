defmodule HologramFeatureTests.Components.Actions.Component19 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_props, component, _server) do
    component
    |> put_state(execution_count: 0, result: nil)
    |> put_action(:component_19_action_a)
  end

  def action(:component_19_action_a, _params, component) do
    put_state(component,
      execution_count: component.state.execution_count + 1,
      result: {:component_19_action_a, component.state.execution_count + 1}
    )
  end

  def action(:component_19_action_b, _params, component) do
    put_state(component, :result, {:component_19_action_b, component.state.execution_count})
  end

  @impl true
  def template do
    ~HOLO"""
    <p>
      Component 19 result: <strong id="component_19_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="component_19_action_b">Run Component 19 Action B</button>
    </p>
    """
  end
end
