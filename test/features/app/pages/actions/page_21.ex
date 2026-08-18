defmodule HologramFeatureTests.Actions.Page21 do
  use Hologram.Page

  route "/actions/21"

  layout HologramFeatureTests.Components.PendingActionLayout

  def template do
    ~HOLO"""
    <h1>Page 21 title</h1>
    """
  end
end
