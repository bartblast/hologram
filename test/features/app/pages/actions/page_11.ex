defmodule HologramFeatureTests.Actions.Page11 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.Components.Actions.Component17

  route "/actions/11"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <Component17 cid="component_17" />
    </p>
    """
  end

  def action(:delayed_action_11, _params, component) do
    put_state(component, result: :delayed_action_11_executed)
  end
end
