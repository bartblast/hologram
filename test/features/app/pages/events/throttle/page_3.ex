defmodule HologramFeatureTests.Events.Throttle.Page3 do
  use Hologram.Page

  route "/events/throttle/3"

  layout HologramFeatureTests.Components.ThrottleLayout

  def template do
    ~HOLO"""
    <h1>Throttle page 3</h1>
    """
  end
end
