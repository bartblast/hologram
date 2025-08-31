defmodule HologramFeatureTests.Actions.Page9 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.Components.Actions.Component12
  alias HologramFeatureTests.Components.Actions.Component13
  alias HologramFeatureTests.Components.Actions.Component14
  alias HologramFeatureTests.Components.Actions.Component15
  alias HologramFeatureTests.Components.Actions.Component16

  route "/actions/9"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, combined_result: [], show_components?: false)
  end

  def template do
    ~HOLO"""
    <p>
      Combined result: <strong id="combined_result"><code>{inspect(@combined_result)}</code></strong>
    </p>
    {%if @show_components?}
      <Component12 cid="aaa_component" />
      <Component16 cid="ccc_component" />
      <Component14 cid="mmm_component" />
      <Component15 cid="bbb_component" />
      <Component13 cid="zzz_component" />
    {%else}
      Components are hidden
    {/if}
    <p>
      <button $click="show_components">Show components</button>
    </p>    
    """
  end

  def action(:append_result, params, component) do
    put_state(
      component,
      :combined_result,
      component.state.combined_result ++ [params.action_result]
    )
  end

  def action(:show_components, _params, component) do
    put_state(component, show_components?: true)
  end
end
