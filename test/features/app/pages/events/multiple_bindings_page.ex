defmodule HologramFeatureTests.Events.MultipleBindingsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/multiple-bindings"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      filter_result: nil,
      full_value: nil,
      order_result: [],
      quick_value: nil
    )
  end

  def template do
    ~HOLO"""
    <p>
      <input
        $key_down.enter="record_enter"
        $key_down.escape="record_escape"
        id="filter_input"
        type="text" />
    </p>
    <p>
      Filter: <strong id="filter_result"><code>{inspect(@filter_result)}</code></strong>
    </p>
    <p>
      <input
        $change.debounce(1500)="record_full"
        $change.debounce(500)="record_quick"
        id="layered_input"
        type="text" />
    </p>
    <p>
      Full: <strong id="full_result"><code>{inspect(@full_value)}</code></strong>
    </p>
    <p>
      Quick: <strong id="quick_result"><code>{inspect(@quick_value)}</code></strong>
    </p>
    <p>
      <button $click="record_first" $click="record_second" id="order_button">Click me</button>
    </p>
    <p>
      Order: <strong id="order_result"><code>{inspect(@order_result)}</code></strong>
    </p>
    """
  end

  def action(:record_enter, _params, component) do
    put_state(component, :filter_result, :enter_matched)
  end

  def action(:record_escape, _params, component) do
    put_state(component, :filter_result, :escape_matched)
  end

  def action(:record_first, _params, component) do
    put_state(component, :order_result, component.state.order_result ++ [:first])
  end

  def action(:record_full, params, component) do
    put_state(component, :full_value, params.event.value)
  end

  def action(:record_quick, params, component) do
    put_state(component, :quick_value, params.event.value)
  end

  def action(:record_second, _params, component) do
    put_state(component, :order_result, component.state.order_result ++ [:second])
  end
end
