defmodule HologramFeatureTests.Actions.Page6 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.Components.Actions.Component5
  alias HologramFeatureTests.Components.Actions.Component6
  alias HologramFeatureTests.Components.Actions.Component7
  alias HologramFeatureTests.Components.Actions.Component8
  alias HologramFeatureTests.Components.Actions.Component9

  route "/actions/6"

  layout HologramFeatureTests.Components.LayoutWithQueuedAction

  def init(_params, component, _server) do
    component
    |> put_state(:combined_result, [])
    |> put_action(:page_action)
  end

  def template do
    ~HOLO"""
    <p>
      Combined result: <strong id="combined_result"><code>{inspect(@combined_result)}</code></strong>
    </p>
    <Component5 cid="aaa_component" />
    <Component6 cid="zzz_component" />
    <Component7 cid="mmm_component" />
    <Component8 cid="bbb_component" />
    <Component9 cid="ccc_component" />
    """
  end

  def action(:append_result, params, component) do
    put_state(
      component,
      :combined_result,
      component.state.combined_result ++ [params.action_result]
    )
  end

  def action(:page_action, _params, component) do
    put_action(component, :append_result, action_result: :page_action_executed)
  end
end
