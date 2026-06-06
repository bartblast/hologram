defmodule HologramFeatureTests.Events.ScrollPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/scroll"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      element_scroll: nil,
      window_scroll: nil
    )
  end

  def template do
    ~HOLO"""
    <window $scroll="record_window_scroll" />
    <div $scroll="record_element_scroll" id="scroller" style="width: 100px; height: 100px; overflow: auto">
      <div style="width: 1000px; height: 1000px">Content</div>
    </div>
    <div style="width: 3000px; height: 2000px">Spacer</div>
    <p>
      Element: <strong id="element_result"><code>{inspect(@element_scroll)}</code></strong>
    </p>
    <p>
      Window: <strong id="window_result"><code>{inspect(@window_scroll)}</code></strong>
    </p>
    """
  end

  def action(
        :record_element_scroll,
        %{event: %{scroll_left: scroll_left, scroll_top: scroll_top}},
        component
      ) do
    put_state(component, :element_scroll, {scroll_left, scroll_top})
  end

  def action(
        :record_window_scroll,
        %{event: %{scroll_left: scroll_left, scroll_top: scroll_top}},
        component
      ) do
    put_state(component, :window_scroll, {scroll_left, scroll_top})
  end
end
