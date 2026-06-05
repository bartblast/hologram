defmodule HologramFeatureTests.Events.DocumentPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/document"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      escape_count: 0,
      listening: false,
      shortcut_count: 0
    )
  end

  def template do
    ~HOLO"""
    <document $key_down.ctrl+k="handle_shortcut" />
    {%if @listening}
      <document $key_down.escape="handle_escape" />
    {/if}
    <p>
      <button $click="toggle_listening" id="toggle_listening">Toggle listening</button>
    </p>
    <p>
      Escape: <strong id="escape_result"><code>{inspect(@escape_count)}</code></strong>
    </p>
    <p>
      Shortcut: <strong id="shortcut_result"><code>{inspect(@shortcut_count)}</code></strong>
    </p>
    """
  end

  def action(:handle_escape, _params, component) do
    put_state(component, :escape_count, component.state.escape_count + 1)
  end

  def action(:handle_shortcut, _params, component) do
    put_state(component, :shortcut_count, component.state.shortcut_count + 1)
  end

  def action(:toggle_listening, _params, component) do
    put_state(component, :listening, !component.state.listening)
  end
end
