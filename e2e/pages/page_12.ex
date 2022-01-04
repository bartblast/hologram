defmodule Hologram.E2E.Page12 do
  use Hologram.Page

  route "/e2e/page-12"

  def init do
    %{
      text: ""
    }
  end

  def template do
    ~H"""
    <button id="trigger" on_click="trigger">Trigger</button>
    <div id="target" on_pointer_down="event">Target</div>
    <div id="text">{@text}</div>
    """
  end

  def action(:event, _params, state) do
    Map.put(state, :text, "Handled pointer down event")
  end

  def action(:trigger, _params, state) do
    JS.exec("setTimeout(() => { document.getElementById('target').dispatchEvent(new Event('pointerdown')) }, 100)")
    state
  end
end
