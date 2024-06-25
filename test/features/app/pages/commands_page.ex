defmodule HologramFeatureTests.CommandsPage do
  use Hologram.Page
  alias HologramFeatureTests.Components.Component2

  route "/commands"

  layout HologramFeatureTests.Components.CommandsLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <p>
      <button id="layout_command_2" $click={%Command{name: :layout_command_2, params: %{a: 1, b: 2}, target: "layout"}}> layout_command_2 </button>
      <button id="page_command_2" $click={%Command{name: :page_command_2, params: %{a: 1, b: 2}}}> page_command_2 </button>
      <button id="component_2_command_2" $click={%Command{name: :component_2_command_2, params: %{a: 1, b: 2}, target: "component_2"}}> component_2_command_2 </button>
    </p>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <Component2 cid="component_2" />
    </p>    
    """
  end

  def action(:page_action_1, params, component) do
    put_state(component, :result, {"page_command_1", params})
  end

  def action(:page_action_2, params, component) do
    put_state(component, :result, {"page_command_2", params})
  end

  def action(:page_action_3, params, component) do
    put_state(component, :result, {"page_command_3", params})
  end

  def command(:page_command_1, params, server) do
    put_action(server, :page_action_1, params)
  end

  def command(:page_command_2, params, server) do
    put_action(server, :page_action_2, params)
  end

  def command(:page_command_3, params, server) do
    put_action(server, :page_action_3, params)
  end
end
