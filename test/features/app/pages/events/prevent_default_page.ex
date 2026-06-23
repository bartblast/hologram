defmodule HologramFeatureTests.Events.PreventDefaultPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/prevent-default"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      plain_key: false,
      plain_submit: false,
      prevented_key: false,
      prevented_submit: false
    )
  end

  def template do
    ~HOLO"""
    <form $submit="record_prevented_submit">
      <input $key_down.enter.prevent_default="record_prevented_key" id="prevented_input" type="text" />
    </form>
    <form $submit="record_plain_submit">
      <input $key_down.enter="record_plain_key" id="plain_input" type="text" />
    </form>
    <p>
      Result: <strong id="result"><code>{inspect({@prevented_key, @prevented_submit, @plain_key, @plain_submit})}</code></strong>
    </p>
    """
  end

  def action(:record_plain_key, _params, component) do
    put_state(component, :plain_key, true)
  end

  def action(:record_plain_submit, _params, component) do
    put_state(component, :plain_submit, true)
  end

  def action(:record_prevented_key, _params, component) do
    put_state(component, :prevented_key, true)
  end

  def action(:record_prevented_submit, _params, component) do
    put_state(component, :prevented_submit, true)
  end
end
