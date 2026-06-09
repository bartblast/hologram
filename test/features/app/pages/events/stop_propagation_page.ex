defmodule HologramFeatureTests.Events.StopPropagationPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/stop-propagation"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      plain_inner: false,
      plain_outer: false,
      stopped_inner: false,
      stopped_outer: false
    )
  end

  def template do
    ~HOLO"""
    <div $click="record_plain_outer">
      <button $click="record_plain_inner" id="plain_button">Plain</button>
    </div>
    <div $click="record_stopped_outer">
      <button $click.stop_propagation="record_stopped_inner" id="stopped_button">Stopped</button>
    </div>
    <p>
      Result: <strong id="result"><code>{inspect({@plain_inner, @plain_outer, @stopped_inner, @stopped_outer})}</code></strong>
    </p>
    """
  end

  def action(:record_plain_inner, _params, component) do
    put_state(component, :plain_inner, true)
  end

  def action(:record_plain_outer, _params, component) do
    put_state(component, :plain_outer, true)
  end

  def action(:record_stopped_inner, _params, component) do
    put_state(component, :stopped_inner, true)
  end

  def action(:record_stopped_outer, _params, component) do
    put_state(component, :stopped_outer, true)
  end
end
