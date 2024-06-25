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
    </p>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <Component2 cid="component_2" />
    </p>    
    """
  end
end
