defmodule HologramFeatureTests.Events.Throttle.Page1 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/throttle/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      plain_count: 0,
      plain_key: nil,
      throttled_count: 0,
      throttled_key: nil
    )
  end

  def template do
    ~HOLO"""
    <p>
      <input
        $key_down="record_plain"
        $key_down.throttle(500)="record_throttled"
        id="my_input"
        type="text" />
    </p>
    <p>
      Throttled: <strong id="throttled_result"><code>{inspect({@throttled_count, @throttled_key})}</code></strong>
    </p>
    <p>
      Plain: <strong id="plain_result"><code>{inspect({@plain_count, @plain_key})}</code></strong>
    </p>
    """
  end

  def action(:record_plain, params, component) do
    put_state(component,
      plain_count: component.state.plain_count + 1,
      plain_key: params.event.key
    )
  end

  def action(:record_throttled, params, component) do
    put_state(component,
      throttled_count: component.state.throttled_count + 1,
      throttled_key: params.event.key
    )
  end
end
