defmodule HologramFeatureTests.Events.AllowDefault.Page1 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/allow-default/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, allowed: false, prevented: false)
  end

  def template do
    ~HOLO"""
    <form action="/events/allow-default/2" method="get" $submit.allow_default="record_allowed">
      <button id="allowed_submit" type="submit">Allowed</button>
    </form>
    <form action="/events/allow-default/2" method="get" $submit="record_prevented">
      <button id="prevented_submit" type="submit">Prevented</button>
    </form>
    <p>
      Result: <strong id="result"><code>{inspect({@allowed, @prevented})}</code></strong>
    </p>
    """
  end

  def action(:record_allowed, _params, component) do
    put_state(component, :allowed, true)
  end

  def action(:record_prevented, _params, component) do
    put_state(component, :prevented, true)
  end
end
