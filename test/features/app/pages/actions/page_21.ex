defmodule HologramFeatureTests.Actions.Page21 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Actions.Page20

  route "/actions/21"

  layout HologramFeatureTests.Components.PendingActionLayout

  def template do
    ~HOLO"""
    <h1>Page 21 title</h1>
    <Link to={Page20}>Page 20 link</Link>
    """
  end
end
