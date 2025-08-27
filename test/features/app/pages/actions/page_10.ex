defmodule HologramFeatureTests.Actions.Page10 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/10"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:result, nil)
    |> put_action(name: :delayed_action_10, delay: 3_000)
  end

  def template do
    ~HOLO"""
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:delayed_action_10, _params, component) do
    put_state(component, result: :delayed_action_10_executed)
  end
end
