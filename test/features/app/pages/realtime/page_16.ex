defmodule HologramFeatureTests.Realtime.Page16 do
  use Hologram.Page

  alias HologramFeatureTests.Realtime.Component4

  route "/realtime/16"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component4 cid="component_4" />
    """
  end
end
