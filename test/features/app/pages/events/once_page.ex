defmodule HologramFeatureTests.Events.OncePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/once"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      click_count: 0,
      rearm_count: 0,
      rearm_shown: true,
      rerender_tick: 0,
      resize_once_count: 0,
      resize_plain_count: 0
    )
  end

  # The re-arm button is the sole child of its own <p> so that hiding it destroys the DOM node and
  # showing it creates a fresh one. Sharing a parent with siblings would let the reconciler reuse the
  # node by position, leaving the same element instance in place and the binding spent.
  def template do
    ~HOLO"""
    <p>
      <button $click.once="record_click" id="click_button">Click</button>
    </p>
    <p>
      Click: <strong id="click_result"><code>{inspect(@click_count)}</code></strong>
    </p>
    <p>
      {%if @rearm_shown}
        <button $click.once="record_rearm" id="rearm_button">Rearm</button>
      {/if}
    </p>
    <p>
      <button $click="rerender" id="rerender_button">Rerender</button>
      <button $click="toggle_rearm" id="toggle_button">Toggle</button>
    </p>
    <p>
      Rearm: <strong id="rearm_result"><code>{inspect(@rearm_count)}</code></strong>
    </p>
    <div $resize.once="record_resize_once" id="resize_once_box" style="width: 100px; height: 50px">Once</div>
    <div $resize="record_resize_plain" id="resize_plain_box" style="width: 100px; height: 50px">Plain</div>
    <p>
      Resize once: <strong id="resize_once_result"><code>{inspect(@resize_once_count)}</code></strong>
    </p>
    <p>
      Resize plain: <strong id="resize_plain_result"><code>{inspect(@resize_plain_count)}</code></strong>
    </p>
    """
  end

  def action(:record_click, _params, component) do
    put_state(component, :click_count, component.state.click_count + 1)
  end

  def action(:record_rearm, _params, component) do
    put_state(component, :rearm_count, component.state.rearm_count + 1)
  end

  def action(:record_resize_once, _params, component) do
    put_state(component, :resize_once_count, component.state.resize_once_count + 1)
  end

  def action(:record_resize_plain, _params, component) do
    put_state(component, :resize_plain_count, component.state.resize_plain_count + 1)
  end

  def action(:rerender, _params, component) do
    put_state(component, :rerender_tick, component.state.rerender_tick + 1)
  end

  def action(:toggle_rearm, _params, component) do
    put_state(component, :rearm_shown, !component.state.rearm_shown)
  end
end
