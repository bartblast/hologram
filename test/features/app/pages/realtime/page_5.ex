defmodule HologramFeatureTests.Realtime.Page5 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Realtime.Page6

  route "/realtime/5"

  layout HologramFeatureTests.Components.RealtimeLayout

  def template do
    ~HOLO"""
    <h1>Page 5</h1>
    <Link to={Page6}>Go to Page 6</Link>
    """
  end
end
