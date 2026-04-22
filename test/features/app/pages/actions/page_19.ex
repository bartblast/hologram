defmodule HologramFeatureTests.Actions.Page19 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/19"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, execution_count: 0, result: nil)
  end

  def template do
    ~HOLO"""
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="page_19_action_a">Run Page 19 Action A</button>
      <button $click="page_19_action_c">Run Page 19 Action C</button>
    </p>
    """
  end

  def action(:page_19_action_a, _params, component) do
    put_action(component, :page_19_action_b)
  end

  def action(:page_19_action_b, _params, component) do
    new_execution_count = component.state.execution_count + 1

    put_state(component,
      execution_count: new_execution_count,
      result: {:page_19_action_b, new_execution_count}
    )
  end

  def action(:page_19_action_c, _params, component) do
    put_state(component, :result, {:page_19_action_c, component.state.execution_count})
  end
end
