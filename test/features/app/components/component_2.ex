defmodule HologramFeatureTests.Components.Component2 do
  use Hologram.Component

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <p>
      <button id="layout_command_3" $click={%Command{name: :layout_command_3, params: %{a: 1, b: 2}, target: "layout"}}> layout_command_3 </button>
      <button id="page_command_3" $click={%Command{name: :page_command_3, params: %{a: 1, b: 2}, target: "page"}}> page_command_3 </button>
    </p>        
    <p>
      Component 2 result: <strong id="component_2_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end
end
