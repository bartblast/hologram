defmodule HologramFeatureTests.Actions.Page5 do
  use Hologram.Page
  alias HologramFeatureTests.Components.Actions.Component3

  route "/actions/5"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component3 cid="component_3" />
    """
  end
end
