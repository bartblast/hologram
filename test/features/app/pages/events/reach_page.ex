defmodule HologramFeatureTests.Events.ReachPage do
  use Hologram.Page

  route "/events/reach"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      filled_bottom: 0,
      filled_right: 0,
      hidden_child_bottom: 0,
      scroll_bottom: 0,
      scroll_left: 0,
      scroll_right: 0,
      scroll_top: 0
    )
  end

  def template do
    ~HOLO"""
    <div
      $reach_bottom.within(200px)="scroll_bottom"
      $reach_top="scroll_top"
      id="scrollable_vertical"
      style="height: 100px; overflow: auto"
    >
      <div style="height: 20px">Top</div>
      <div style="height: 960px">Spacer</div>
      <div style="height: 20px">Bottom</div>
    </div>
    <div
      $reach_left="scroll_left"
      $reach_right="scroll_right"
      id="scrollable_horizontal"
      style="display: flex; overflow: auto; width: 100px"
    >
      <div style="flex: 0 0 20px">Left</div>
      <div style="flex: 0 0 960px">Spacer</div>
      <div style="flex: 0 0 20px">Right</div>
    </div>
    <div $reach_bottom="filled_bottom" id="filled_vertical" style="height: 100px; overflow: auto">
      <div style="height: 20px">Top</div>
      <div style="height: 20px">Bottom</div>
    </div>
    <div
      $reach_right="filled_right"
      id="filled_horizontal"
      style="display: flex; overflow: auto; width: 100px"
    >
      <div style="flex: 0 0 20px">Left</div>
      <div style="flex: 0 0 20px">Right</div>
    </div>
    <div $reach_bottom="hidden_child_bottom" id="hidden_child_vertical" style="height: 100px; overflow: auto">
      <div style="height: 20px">Top</div>
      <div style="height: 960px">Spacer</div>
      <div style="height: 20px">Bottom</div>
      <div style="display: none">Hidden</div>
    </div>
    <p>
      Scroll top: <strong id="scroll_top_result"><code>{@scroll_top}</code></strong>
    </p>
    <p>
      Scroll bottom: <strong id="scroll_bottom_result"><code>{@scroll_bottom}</code></strong>
    </p>
    <p>
      Filled bottom: <strong id="filled_bottom_result"><code>{@filled_bottom}</code></strong>
    </p>
    <p>
      Scroll left: <strong id="scroll_left_result"><code>{@scroll_left}</code></strong>
    </p>
    <p>
      Scroll right: <strong id="scroll_right_result"><code>{@scroll_right}</code></strong>
    </p>
    <p>
      Filled right: <strong id="filled_right_result"><code>{@filled_right}</code></strong>
    </p>
    <p>
      Hidden child bottom: <strong id="hidden_child_bottom_result"><code>{@hidden_child_bottom}</code></strong>
    </p>
    """
  end

  def action(:filled_bottom, _params, component) do
    put_state(component, :filled_bottom, component.state.filled_bottom + 1)
  end

  def action(:filled_right, _params, component) do
    put_state(component, :filled_right, component.state.filled_right + 1)
  end

  def action(:hidden_child_bottom, _params, component) do
    put_state(component, :hidden_child_bottom, component.state.hidden_child_bottom + 1)
  end

  def action(:scroll_bottom, _params, component) do
    put_state(component, :scroll_bottom, component.state.scroll_bottom + 1)
  end

  def action(:scroll_left, _params, component) do
    put_state(component, :scroll_left, component.state.scroll_left + 1)
  end

  def action(:scroll_right, _params, component) do
    put_state(component, :scroll_right, component.state.scroll_right + 1)
  end

  def action(:scroll_top, _params, component) do
    put_state(component, :scroll_top, component.state.scroll_top + 1)
  end
end
