defmodule HologramFeatureTests.Actions.Page16 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/16"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(execution_count: 0, result: nil)
    |> put_action(:page_16_action_a)
  end

  def template do
    ~HOLO"""
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="page_16_action_b">Run Page 16 Action B</button>
    </p>
    """
  end

  def action(:page_16_action_a, _params, component) do
    new_execution_count = component.state.execution_count + 1

    put_state(component,
      execution_count: new_execution_count,
      result: {:page_16_action_a, new_execution_count}
    )
  end

  def action(:page_16_action_b, _params, component) do
    put_state(component, :result, {:page_16_action_b, component.state.execution_count})
  end
end
