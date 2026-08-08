defmodule HologramFeatureTests.Queries.Page1 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Queries.Component1

  route "/queries/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component1 cid="component_1" />
    """
  end
end
