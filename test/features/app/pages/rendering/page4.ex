defmodule HologramFeatureTests.Rendering.Page4 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Rendering.Component1

  route "/rendering/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component1 cid="component_1" text="a & b < c" />
    """
  end
end
