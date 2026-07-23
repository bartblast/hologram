defmodule HologramFeatureTests.Events.Debounce.Page3 do
  use Hologram.Page

  route "/events/debounce/3"

  layout HologramFeatureTests.Components.DebounceLayout

  def template do
    ~HOLO"""
    <h1>Debounce page 3</h1>
    """
  end
end
