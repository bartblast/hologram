defmodule HologramFeatureTests.Components.Actions.Component4 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      Component 4 result: <strong id="component_4_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:component_4_action, params, component) do
    put_state(component, :result, {:component_4_action_result, params.x + 1})
  end
end
