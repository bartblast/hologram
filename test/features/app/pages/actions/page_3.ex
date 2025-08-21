defmodule HologramFeatureTests.Actions.Page3 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.Components.Actions.Component1

  route "/actions/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:result, nil)
    |> put_action(name: :component_action, params: %{x: 333}, target: "component_1")
  end

  def template do
    ~HOLO"""
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <Component1 cid="component_1" />
    """
  end
end
