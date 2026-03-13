defmodule HologramFeatureTests.Actions.Page16 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/16"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(execution_count: 0, result: nil)
    |> put_action(:page_action_16a)
  end

  def template do
    ~HOLO"""
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="page_action_16b">Run Action 16b</button>
    </p>
    """
  end

  def action(:page_action_16a, _params, component) do
    put_state(component,
      execution_count: component.state.execution_count + 1,
      result: {:page_action_16a, component.state.execution_count}
    )
  end

  def action(:page_action_16b, _params, component) do
    put_state(component, :result, {:page_action_16b, component.state.execution_count})
  end
end
