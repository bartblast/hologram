defmodule HologramFeatureTests.Queries.Page3 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Queries.Component3
  alias HologramFeatureTests.Components.Queries.Component5
  alias HologramFeatureTests.Components.Queries.Component6
  alias HologramFeatureTests.Entities.Review

  route "/queries/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component3 cid="component_3" />
    <Component5 cid="component_5" sort_field={:rating} />
    <Component6 cid="component_6" entity_type={Review} />
    """
  end
end
