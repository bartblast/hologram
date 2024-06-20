defmodule HologramFeatureTests.ActionsPage do
  use Hologram.Page

  route "/actions"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <p>
      <button id="action_1" $click="action_1"> action_1 </button>
      <button id="action_2" $click={:action_2}> action_2 </button>
      <button id="action_3" $click={:action_3, a: 1, b: 2}> action_3 </button>
      <button id="action_4" $click={%Action{name: :action_4, params: %{a: 1, b: 2}}}> action_4 </button>
      <button id="action_5" $click="ac{"ti"}on_{5}"> action_5 </button>
    </p>
    <p>
      Page result: <strong id="result">{inspect(@result)}</strong>
    </p>   
    """
  end

  def action(:action_1, params, component) do
    put_state(component, :result, {"action_1", params})
  end

  def action(:action_2, params, component) do
    put_state(component, :result, {"action_2", params})
  end

  def action(:action_3, params, component) do
    put_state(component, :result, {"action_3", params})
  end

  def action(:action_4, params, component) do
    put_state(component, :result, {"action_4", params})
  end

  def action(:action_5, params, component) do
    put_state(component, :result, {"action_5", params})
  end
end
