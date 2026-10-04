defmodule HologramFeatureTests.Components.Actions.Component22 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_props, component, _server) do
    put_state(component, :count, 0)
  end

  def template do
    ~HOLO"""
    <p>
      Component 22 count: <strong id="component_22_count"><code>{inspect(@count)}</code></strong>
    </p>
    <p>
      <button $click="increment">Increment component 22</button>
    </p>
    """
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end
end
