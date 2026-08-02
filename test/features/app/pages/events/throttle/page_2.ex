defmodule HologramFeatureTests.Events.Throttle.Page2 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Events.Throttle.Page3

  route "/events/throttle/2"

  layout HologramFeatureTests.Components.ThrottleLayout

  def template do
    ~HOLO"""
    <h1>Throttle page 2</h1>
    <Link to={Page3}>Page 3 link</Link>
    """
  end
end
