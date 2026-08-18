defmodule HologramFeatureTests.Components.Actions.Component21 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  # Mounted on one page only, so its cid is registered nowhere once the user navigates away.
  def init(_props, component, _server) do
    put_state(component, :result, nil)
  end

  def action(:record_component_action, _params, component) do
    put_state(component, :result, "component_action_ran")
  end

  def template do
    ~HOLO"""
    <p>
      Component 21 result:
      <strong id="component_21_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end
end
