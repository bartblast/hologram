defmodule HologramFeatureTests.Events.Debounce.Page2 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Events.Debounce.Page3

  route "/events/debounce/2"

  layout HologramFeatureTests.Components.DebounceLayout

  def template do
    ~HOLO"""
    <h1>Debounce page 2</h1>
    <Link to={Page3}>Page 3 link</Link>
    """
  end
end
