defmodule HologramFeatureTests.Events.Debounce.Page4 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/debounce/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, editor_open: true, typed_value: nil)
  end

  def template do
    ~HOLO"""
    {%if @editor_open}
      <div id="editor_block">
        <input
          $change.debounce(600000)="record_typed"
          $key_down.escape="close_editor"
          id="editor_input"
          type="text" />
        <p id="editor_hint">Press Escape to close</p>
      </div>
    {/if}
    <p>
      Typed: <strong id="typed_result"><code>{inspect(@typed_value)}</code></strong>
    </p>
    """
  end

  def action(:close_editor, _params, component) do
    put_state(component, :editor_open, false)
  end

  def action(:record_typed, params, component) do
    put_state(component, :typed_value, params.event.value)
  end
end
