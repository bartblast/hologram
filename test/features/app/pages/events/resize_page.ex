defmodule HologramFeatureTests.Events.ResizePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/resize"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      element_resize: nil,
      window_resize: nil
    )
  end

  def template do
    ~HOLO"""
    <window $resize="record_window_resize" />
    <div $resize="record_element_resize" id="resizable" style="box-sizing: border-box; width: 200px; height: 100px; padding: 10px; border: 5px solid">Content</div>
    <p>
      Element: <strong id="element_result"><code>{inspect(@element_resize)}</code></strong>
    </p>
    <p>
      Window: <strong id="window_result"><code>{inspect(@window_resize)}</code></strong>
    </p>
    """
  end

  def action(:record_element_resize, %{event: event}, component) do
    put_state(component, :element_resize, event)
  end

  def action(:record_window_resize, %{event: event}, component) do
    put_state(component, :window_resize, event)
  end
end
