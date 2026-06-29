defmodule HologramFeatureTests.Components.Events.ReachNested do
  use Hologram.Component

  def init(_props, component, _server) do
    put_state(component, :nested_bottom, 0)
  end

  def template do
    ~HOLO"""
    <div $reach_bottom="nested_bottom" id="nested_vertical" style="height: 100px; overflow: auto">
      <div style="height: 20px">Top</div>
      <div style="height: 20px">Bottom</div>
    </div>
    <p>
      Nested bottom: <strong id="nested_bottom_result"><code>{@nested_bottom}</code></strong>
    </p>
    """
  end

  def action(:nested_bottom, _params, component) do
    put_state(component, :nested_bottom, component.state.nested_bottom + 1)
  end
end
