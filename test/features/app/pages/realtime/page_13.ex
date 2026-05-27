defmodule HologramFeatureTests.Realtime.Page13 do
  use Hologram.Page

  alias HologramFeatureTests.Realtime.Component1
  alias HologramFeatureTests.Realtime.Component3

  route "/realtime/13"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component1 cid="component_1" />
    <Component3 cid="component_3" />
    """
  end
end
