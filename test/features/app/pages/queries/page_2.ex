defmodule HologramFeatureTests.Queries.Page2 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Queries.Component2
  alias HologramFeatureTests.Components.Queries.Component7

  route "/queries/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component2 />
    <Component7 cid="component_7" />
    """
  end
end
