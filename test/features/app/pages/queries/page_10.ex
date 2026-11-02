defmodule HologramFeatureTests.Queries.Page10 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Queries.Component18

  route "/queries/10"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component18 cid="component_18" />
    """
  end
end
