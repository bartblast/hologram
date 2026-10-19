defmodule HologramFeatureTests.Events.ReachPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.Events.ReachNested

  route "/events/reach"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      chat_loads: 0,
      chat_messages: Enum.to_list(50..31//-1),
      filled_bottom: 0,
      filled_right: 0,
      hidden_child_bottom: 0,
      resize_bottom: 0,
      reversed_bottom: 0,
      reversed_top: 0,
      rtl_left: 0,
      rtl_right: 0,
      scroll_bottom: 0,
      scroll_left: 0,
      scroll_right: 0,
      scroll_top: 0,
      tall_child_bottom: 0
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
    <div $reach_bottom.within(200px)="tall_child_bottom" id="tall_child_vertical" style="height: 100px; overflow: auto">
      <div style="height: 20px">Top</div>
      <div style="height: 600px">Spacer</div>
      <div style="height: 400px">Tall</div>
    </div>
    <div $reach_bottom="resize_bottom" id="resize_vertical" style="height: 100px; overflow: auto">
      <div style="height: 20px">Top</div>
      <div id="resize_spacer" style="height: 200px">Spacer</div>
      <div style="height: 20px">Bottom</div>
    </div>
    <div
      $reach_bottom.within(200px)="reversed_bottom"
      $reach_top="reversed_top"
      id="reversed_vertical"
      style="display: flex; flex-direction: column-reverse; height: 100px; overflow: auto"
    >
      <div style="flex: 0 0 20px">Bottom</div>
      <div style="flex: 0 0 960px">Spacer</div>
      <div style="flex: 0 0 20px">Top</div>
    </div>
    <div
      $reach_left="rtl_left"
      $reach_right="rtl_right"
      id="rtl_horizontal"
      style="direction: rtl; display: flex; overflow: auto; width: 100px"
    >
      <div style="flex: 0 0 20px">Right</div>
      <div style="flex: 0 0 960px">Spacer</div>
      <div style="flex: 0 0 20px">Left</div>
    </div>
    <div
      $reach_top="chat_load_older"
      id="chat_vertical"
      style="display: flex; flex-direction: column-reverse; height: 100px; overflow: auto"
    >
      {%for message <- @chat_messages}
        <div style="flex: 0 0 50px">Message {message}</div>
      {/for}
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
    <p>
      Tall child bottom: <strong id="tall_child_bottom_result"><code>{@tall_child_bottom}</code></strong>
    </p>
    <p>
      Resize bottom: <strong id="resize_bottom_result"><code>{@resize_bottom}</code></strong>
    </p>
    <p>
      Reversed top: <strong id="reversed_top_result"><code>{@reversed_top}</code></strong>
    </p>
    <p>
      Reversed bottom: <strong id="reversed_bottom_result"><code>{@reversed_bottom}</code></strong>
    </p>
    <p>
      RTL left: <strong id="rtl_left_result"><code>{@rtl_left}</code></strong>
    </p>
    <p>
      RTL right: <strong id="rtl_right_result"><code>{@rtl_right}</code></strong>
    </p>
    <p>
      Chat loads: <strong id="chat_loads_result"><code>{@chat_loads}</code></strong>
    </p>
    <ReachNested cid="reach_nested" />
    """
  end

  def action(:chat_load_older, _params, component) do
    oldest = List.last(component.state.chat_messages)
    older = Enum.to_list((oldest - 1)..(oldest - 10)//-1)

    component
    |> put_state(:chat_loads, component.state.chat_loads + 1)
    |> put_state(:chat_messages, component.state.chat_messages ++ older)
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

  def action(:resize_bottom, _params, component) do
    put_state(component, :resize_bottom, component.state.resize_bottom + 1)
  end

  def action(:reversed_bottom, _params, component) do
    put_state(component, :reversed_bottom, component.state.reversed_bottom + 1)
  end

  def action(:reversed_top, _params, component) do
    put_state(component, :reversed_top, component.state.reversed_top + 1)
  end

  def action(:rtl_left, _params, component) do
    put_state(component, :rtl_left, component.state.rtl_left + 1)
  end

  def action(:rtl_right, _params, component) do
    put_state(component, :rtl_right, component.state.rtl_right + 1)
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

  def action(:tall_child_bottom, _params, component) do
    put_state(component, :tall_child_bottom, component.state.tall_child_bottom + 1)
  end
end
