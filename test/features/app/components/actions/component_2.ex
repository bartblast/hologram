defmodule HologramFeatureTests.Components.Actions.Component2 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_params, component, _server) do
    component
    |> put_state(:result, nil)
    |> put_action(:component_2_action, queued_from: :component_2)
  end

  def template do
    ~HOLO"""
    <p>
      Component 2 result: <strong id="component_2_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:component_2_action, params, component) do
    put_state(component, :result, {:component_2_action_result, params})
  end
end
