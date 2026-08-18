defmodule HologramFeatureTests.Actions.Page20 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Actions.Page21
  alias HologramFeatureTests.Components.Actions.Component21

  route "/actions/20"

  layout HologramFeatureTests.Components.PendingActionLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Page 20 title</h1>
    <Component21 cid="component_21" />
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click={action: :record_layout_action, target: "layout", delay: 3_000}>
        Run delayed layout action
      </button>
      <button $click={action: :record_component_action, target: "component_21", delay: 3_000}>
        Run delayed component action
      </button>
      <button $click={action: :page_20_only_action, target: "page", delay: 3_000}>
        Run delayed page action
      </button>
    </p>
    <Link to={Page21}>Page 21 link</Link>
    """
  end

  # Page 21 deliberately has no clause for this, so a dispatch that outlives the navigation
  # lands on a module that cannot answer it.
  def action(:page_20_only_action, _params, component) do
    put_state(component, :result, "page_action_ran")
  end
end
