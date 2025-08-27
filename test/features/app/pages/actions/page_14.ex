defmodule HologramFeatureTests.Actions.Page14 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/14"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, result: nil)
  end

  def template do
    ~HOLO"""
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="instant_action_14">Run instant action</button>
    </p>
    """
  end

  def action(:delayed_action_14, _params, component) do
    put_state(component, result: :delayed_action_14_executed)
  end

  def action(:instant_action_14, _params, component) do
    put_action(component, name: :delayed_action_14, delay: 3_000)
  end
end
