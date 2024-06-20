defmodule HologramFeatureTests.ActionsPage do
  use Hologram.Page
  alias HologramFeatureTests.Components.Component1

  route "/actions"

  layout HologramFeatureTests.Components.ActionsLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <p>
      <button id="page_action_1" $click="page_action_1"> page_action_1 </button>
      <button id="page_action_2" $click={:page_action_2}> page_action_2 </button>
      <button id="page_action_3" $click={:page_action_3, a: 1, b: 2}> page_action_3 </button>
      <button id="page_action_4" $click={%Action{name: :page_action_4, params: %{a: 1, b: 2}}}> page_action_4 </button>
      <button id="page_action_5" $click="page_ac{"ti"}on_{5}"> page_action_5 </button>
      <button id="layout_action_2" $click={%Action{name: :layout_action_2, params: %{a: 1, b: 2}, target: "layout"}}> layout_action_2 </button>
      <button id="component_1_action_2" $click={%Action{name: :component_1_action_2, params: %{a: 1, b: 2}, target: "component_1"}}> component_1_action_2 </button>
    </p>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <Component1 cid="component_1" />
    </p>
    """
  end

  def action(:page_action_1, params, component) do
    put_state(component, :result, {"page_action_1", params})
  end

  def action(:page_action_2, params, component) do
    put_state(component, :result, {"page_action_2", params})
  end

  def action(:page_action_3, params, component) do
    put_state(component, :result, {"page_action_3", params})
  end

  def action(:page_action_4, params, component) do
    put_state(component, :result, {"page_action_4", params})
  end

  def action(:page_action_5, params, component) do
    put_state(component, :result, {"page_action_5", params})
  end
end
