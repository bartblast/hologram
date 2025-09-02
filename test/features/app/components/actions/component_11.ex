defmodule HologramFeatureTests.Components.Actions.Component11 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_props, component) do
    component
    |> put_state(result: nil)
    |> put_action(:component_11_action, queued_from: :component_11)
  end

  def template do
    ~HOLO"""
    <p>
      Component 11 result: <strong id="component_11_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:component_11_action, params, component) do
    put_state(component, result: {:component_11_action_result, params})
  end
end
