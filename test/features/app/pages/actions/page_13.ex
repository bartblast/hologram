defmodule HologramFeatureTests.Actions.Page13 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/13"

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
      <button $click={command: :my_command}>Push command</button>
    </p>
    """
  end

  def action(:delayed_action_13, _params, component) do
    put_state(component, result: :delayed_action_13_executed)
  end

  def command(:my_command, _params, server) do
    put_action(server, name: :delayed_action_13, delay: 3_000)
  end
end
