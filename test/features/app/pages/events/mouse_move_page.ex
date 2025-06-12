defmodule HologramFeatureTests.Events.MouseMovePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/mouse_move"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <div $mouse_move="handle_mouse_move" id="my_div" style="width: 200px; height: 200px; background-color: blue;"></div>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:handle_mouse_move, params, component) do
    put_state(component, :result, params)
  end
end
