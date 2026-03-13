defmodule HologramFeatureTests.Actions.Page17 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Actions.Component19

  route "/actions/17"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component19 cid="component_19" />
    """
  end
end
