defmodule HologramFeatureTests.Events.DragSourcePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/drag_source"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :any

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <div $ref={:task_preview, 42} id="preview">Preview</div>
    </p>
    <p>
      <div
        $data_transfer={
          data: %{"application/x-task" => "42", "text/plain" => "Buy milk", "text/uri-list" => nil},
          effects_allowed: :move,
          image: %{ref: {:task_preview, 42}, x: 16, y: 8}
        }
        $drag_start="drag_started"
        draggable="true"
        id="item"
      >
        Item
        <a href="https://example.com" id="item_link">Link</a>
        <span $data_transfer={data: %{"application/x-tag" => "urgent"}} draggable="true" id="chip">urgent</span>
      </div>
    </p>
    <p>
      <div $data_transfer={drop_effect: :move} $drag_over="dragged_over" $drop="dropped" id="zone">
        <span id="zone_child">Zone child</span>
        <div $data_transfer={drop_effect: :link} $drop="dropped" id="inner_zone">
          <span id="inner_zone_child">Inner zone child</span>
        </div>
      </div>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:drag_started, params, component) do
    put_state(component, :result, {:drag_started, params.event.data_transfer.data})
  end

  def action(:dragged_over, params, component) do
    put_state(component, :result, {:dragged_over, params.event.data_transfer.drop_effect})
  end

  def action(:dropped, params, component) do
    put_state(component, :result, {:dropped, params.event.data_transfer.data})
  end
end
