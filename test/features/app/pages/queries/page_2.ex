defmodule HologramFeatureTests.Queries.Page2 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Queries.Component10
  alias HologramFeatureTests.Components.Queries.Component2
  alias HologramFeatureTests.Components.Queries.Component7
  alias HologramFeatureTests.Components.Queries.Component9

  route "/queries/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component2 />
    <Component7 cid="component_7" />
    <Component9 cid="component_9" />
    <Component10 cid="component_10" />
    """
  end
end
