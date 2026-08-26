defmodule HologramFeatureTests.Events.Throttle.Page3 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Events.Throttle.Page2

  route "/events/throttle/3"

  layout HologramFeatureTests.Components.ThrottleLayout

  def template do
    ~HOLO"""
    <h1>Throttle page 3</h1>
    <Link to={Page2}>Page 2 link</Link>
    """
  end
end
