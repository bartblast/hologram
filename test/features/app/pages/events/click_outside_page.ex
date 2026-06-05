defmodule HologramFeatureTests.Events.ClickOutsidePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/click_outside"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      close_count: 0,
      note_count: 0,
      open?: false
    )
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="open" id="open">Open</button>
      <button id="outside">Outside</button>
    </p>
    {%if @open?}
      <div $click_outside="close" id="panel">
        <button $click="note" id="inside">Inside</button>
      </div>
    {/if}
    <p>
      Close: <strong id="close_result"><code>{inspect(@close_count)}</code></strong>
    </p>
    <p>
      Note: <strong id="note_result"><code>{inspect(@note_count)}</code></strong>
    </p>
    <p>
      Open: <strong id="open_result"><code>{inspect(@open?)}</code></strong>
    </p>
    """
  end

  def action(:close, _params, component) do
    put_state(component,
      close_count: component.state.close_count + 1,
      open?: false
    )
  end

  def action(:note, _params, component) do
    put_state(component, :note_count, component.state.note_count + 1)
  end

  def action(:open, _params, component) do
    put_state(component, :open?, true)
  end
end
