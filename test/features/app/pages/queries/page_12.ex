defmodule HologramFeatureTests.Queries.Page12 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Queries.Component19

  route "/queries/12"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component19 cid="component_19" query="50%" />
    """
  end
end
