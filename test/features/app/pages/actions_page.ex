defmodule HologramFeatureTests.ActionsPage do
  use Hologram.Page
  alias HologramFeatureTests.Components.Component1

  route "/actions"

  layout HologramFeatureTests.Components.ActionsLayout

  def init(_params, component, _server) do
    component
    |> put_state(:result, nil)
    |> put_context(:my_context_key, :initial_value)
  end

  def template do
    ~H"""
    <p>
      <button id="layout_action_2" $click={%Action{name: :layout_action_2, params: %{a: 1, b: 2}, target: "layout"}}> layout_action_2 </button>
      <button id="page_action_1" $click="page_action_1"> page_action_1 </button>
      <button id="page_action_2" $click={:page_action_2}> page_action_2 </button>
      <button id="page_action_3" $click={:page_action_3, a: 1, b: 2}> page_action_3 </button>
      <button id="page_action_4" $click={%Action{name: :page_action_4, params: %{a: 1, b: 2}}}> page_action_4 </button>
      <button id="page_action_5" $click="page_ac{"ti"}on_{5}"> page_action_5 </button>
      <button id="page_action_8" $click="page_action_8"> page_action_8 </button>
      <button id="page_action_9" $click={:page_action_9, a: 1, b: 2}> page_action_9 </button>
      <button id="page_action_11" $click={:page_action_11, a: 1, b: 2}> page_action_11 </button>
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

  def action(:page_action_6, params, component) do
    put_state(component, :result, {"page_action_6", params})
  end

  def action(:page_action_7, params, component) do
    put_state(component, :result, {"page_action_7", params})
  end

  def action(:page_action_8, _params, component) do
    put_context(component, :my_context_key, :updated_value)
  end

  def action(:page_action_9, params, component) do
    component
    |> put_state(:result, {"page_action_9", params})
    |> put_action(:page_action_10, x: 10, y: 20)
  end

  def action(:page_action_10, params, component) do
    put_state(component, :result, {"page_action_10", params})
  end

  def action(:page_action_11, params, component) do
    component
    |> put_state(:result, {"page_action_11", params})
    |> put_command(:page_command_1, x: 10, y: 20)
  end

  def action(:page_action_12, params, component) do
    put_state(component, :result, {"page_action_12", params})
  end

  def command(:page_command_1, params, server) do
    put_action(server, :page_action_12, params)
  end
end
