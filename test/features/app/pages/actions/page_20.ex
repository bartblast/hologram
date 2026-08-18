defmodule HologramFeatureTests.Actions.Page20 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Actions.Page21
  alias HologramFeatureTests.Components.Actions.Component21

  route "/actions/20"

  layout HologramFeatureTests.Components.PendingActionLayout

  def template do
    ~HOLO"""
    <h1>Page 20 title</h1>
    <Component21 cid="component_21" />
    <p>
      <button $click={action: :record_layout_action, target: "layout", delay: 3_000}>
        Run delayed layout action
      </button>
      <button $click={action: :record_component_action, target: "component_21", delay: 3_000}>
        Run delayed component action
      </button>
    </p>
    <Link to={Page21}>Page 21 link</Link>
    """
  end
end
