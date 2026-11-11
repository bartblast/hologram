defmodule HologramFeatureTests.Events.DragAndDropWindowPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/drag_and_drop_window"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :any

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <window $drop="dropped" />
    <p>
      <div id="area">Area</div>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:dropped, params, component) do
    put_state(component, :result, {:dropped, params.event.data_transfer.data})
  end
end
