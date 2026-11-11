defmodule HologramFeatureTests.Events.DragAndDropPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/drag_and_drop"

  layout HologramFeatureTests.Components.DefaultLayout

  state :enter_count, :integer
  state :leave_count, :integer
  state :result, :any

  def init(_params, component, _server) do
    put_state(component, enter_count: 0, leave_count: 0, result: nil)
  end

  def template do
    ~HOLO"""
    <p>
      <div $drag_start="drag_started" draggable="true" id="item">Item</div>
    </p>
    <p>
      <div $drag_enter="drag_entered" $drag_leave="drag_left" $drop="dropped" id="zone" style="padding: 20px; background-color: lightblue;">
        <span id="zone_child">Zone child</span>
      </div>
    </p>
    <p>
      <div $drop="dropped" id="target">
        <span id="target_child">Target child</span>
      </div>
    </p>
    <p>
      <div $drop={nil} id="nil_target">
        <span id="nil_target_child">Nil target child</span>
      </div>
    </p>
    <p>
      Enter count: <strong id="enter_count"><code>{inspect(@enter_count)}</code></strong>
    </p>
    <p>
      Leave count: <strong id="leave_count"><code>{inspect(@leave_count)}</code></strong>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:drag_entered, _params, component) do
    put_state(component, :enter_count, component.state.enter_count + 1)
  end

  def action(:drag_left, _params, component) do
    put_state(component, :leave_count, component.state.leave_count + 1)
  end

  def action(:drag_started, params, component) do
    %{data: data, files: files, items: items, types: types} = params.event.data_transfer

    put_state(
      component,
      :result,
      {:drag_started, %{data: data, files: files, items: items, types: types}}
    )
  end

  def action(:dropped, params, component) do
    %{data: data, files: files, types: types} = params.event.data_transfer

    file_details =
      Enum.map(files, fn %Hologram.File{path: path} ->
        {Path.basename(path), MIME.from_path(path),
         String.starts_with?(path, "/$hologram/drops/")}
      end)

    put_state(component, :result, {:dropped, %{data: data, files: file_details, types: types}})
  end
end
