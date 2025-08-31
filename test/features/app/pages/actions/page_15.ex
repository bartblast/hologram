defmodule HologramFeatureTests.Actions.Page15 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/15"

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
      <button $click={action: :delayed_action_15, delay: 3_000}>Run delayed action</button>
    </p>
    """
  end

  def action(:delayed_action_15, _params, component) do
    put_state(component, result: :delayed_action_15_executed)
  end
end
