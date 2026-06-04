defmodule HologramFeatureTests.Events.AllowDefaultPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/allow-default"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, allowed: false, blocked: false)
  end

  def template do
    ~HOLO"""
    <p>
      <input $click.allow_default="record_allowed" id="allowed_checkbox" type="checkbox" />
      <input $click="record_blocked" id="blocked_checkbox" type="checkbox" />
    </p>
    <p>
      Result: <strong id="result"><code>{inspect({@allowed, @blocked})}</code></strong>
    </p>
    """
  end

  def action(:record_allowed, _params, component) do
    put_state(component, :allowed, true)
  end

  def action(:record_blocked, _params, component) do
    put_state(component, :blocked, true)
  end
end
