defmodule HologramFeatureTests.Actions.Page7 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.Components.Actions.Component10

  route "/actions/7"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, result: nil, show_component?: false)
  end

  def template do
    ~HOLO"""
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>    
    {%if @show_component?}
      <Component10 cid="component_10" />
    {%else}
      Component10 is hidden
    {/if}
    <p>
      <button $click="show_component">Show component</button>
    </p>    
    """
  end

  def action(:page_action, params, component) do
    put_state(component, result: {:page_action_result, params})
  end

  def action(:show_component, _params, component) do
    put_state(component, show_component?: true)
  end
end
