defmodule HologramFeatureTests.Events.DebouncePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/debounce"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      blurred_value: nil,
      debounced_count: 0,
      debounced_key: nil,
      plain_count: 0,
      plain_key: nil
    )
  end

  def template do
    ~HOLO"""
    <p>
      <input
        $key_down="record_plain"
        $key_down.debounce(500)="record_debounced"
        id="my_input"
        type="text" />
    </p>
    <p>
      Debounced: <strong id="debounced_result"><code>{inspect({@debounced_count, @debounced_key})}</code></strong>
    </p>
    <p>
      Plain: <strong id="plain_result"><code>{inspect({@plain_count, @plain_key})}</code></strong>
    </p>
    <p>
      <input
        $change.debounce(600000)="record_blurred"
        id="blur_input"
        type="text" />
    </p>
    <p>
      Blurred: <strong id="blurred_result"><code>{inspect(@blurred_value)}</code></strong>
    </p>
    """
  end

  def action(:record_blurred, params, component) do
    put_state(component, :blurred_value, params.event.value)
  end

  def action(:record_debounced, params, component) do
    put_state(component,
      debounced_count: component.state.debounced_count + 1,
      debounced_key: params.event.key
    )
  end

  def action(:record_plain, params, component) do
    put_state(component,
      plain_count: component.state.plain_count + 1,
      plain_key: params.event.key
    )
  end
end
