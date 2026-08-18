defmodule HologramFeatureTests.Actions.Page20 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Actions.Page21

  route "/actions/20"

  layout HologramFeatureTests.Components.PendingActionLayout

  def template do
    ~HOLO"""
    <h1>Page 20 title</h1>
    <p>
      <button $click={action: :record_layout_action, target: "layout", delay: 3_000}>
        Run delayed layout action
      </button>
    </p>
    <Link to={Page21}>Page 21 link</Link>
    """
  end
end
