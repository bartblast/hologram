defmodule HologramFeatureTests.Queries.Page2 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Queries.Component2

  route "/queries/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component2 />
    """
  end
end
