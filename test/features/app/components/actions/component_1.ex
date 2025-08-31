defmodule HologramFeatureTests.Components.Actions.Component1 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      Component 1 result: <strong id="component_1_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:component_1_action, params, component) do
    put_state(component, :result, {:component_1_action_result, params})
  end
end
