defmodule HologramFeatureTests.Actions.Page12 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.Components.Actions.Component18

  route "/actions/12"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, result: nil, show_component?: false)
  end

  def template do
    ~HOLO"""
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      {%if @show_component?}
        <Component18 cid="component_18" />
      {%else}
        <button $click="show_component">Show component</button>
      {/if}
    </p>
    """
  end

  def action(:delayed_action_12, _params, component) do
    put_state(component, result: :delayed_action_12_executed)
  end

  def action(:show_component, _params, component) do
    put_state(component, show_component?: true)
  end
end
