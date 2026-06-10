defmodule HologramFeatureTests.Events.DisabledBindingPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/disabled-binding"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      conditional: nil,
      conditional_with_params: nil,
      enabled: false,
      pong: false
    )
  end

  def template do
    ~HOLO"""
    <p>
      <button id="conditional" $click={if @enabled do :conditional_action end}>Conditional</button>
      <button id="conditional_with_params" $click={if @enabled do :conditional_action_with_params end, x: 1}>Conditional with params</button>
      <button id="disabled_longhand_action" $click={action: nil}>Disabled longhand action</button>
      <button id="disabled_longhand_action_with_params" $click={action: nil, params: %{a: 1}}>Disabled longhand action with params</button>
      <button id="disabled_longhand_command" $click={command: nil}>Disabled longhand command</button>
      <button id="disabled_shorthand" $click={nil}>Disabled shorthand</button>
      <button id="enable" $click="enable">Enable</button>
      <button id="ping" $click="ping">Ping</button>
    </p>
    <p>
      <input id="checkbox" type="checkbox" $click={nil} />
    </p>
    <p>
      Result: <strong id="result"><code>{inspect({@conditional, @conditional_with_params, @enabled, @pong})}</code></strong>
    </p>
    """
  end

  def action(:conditional_action, _params, component) do
    put_state(component, :conditional, :executed)
  end

  def action(:conditional_action_with_params, params, component) do
    put_state(component, :conditional_with_params, params.x)
  end

  def action(:enable, _params, component) do
    put_state(component, :enabled, true)
  end

  def action(:ping, _params, component) do
    put_state(component, :pong, true)
  end
end
