defmodule HologramCowboyTests.PlainPage do
  use Hologram.Page

  route "/plain"

  layout HologramCowboyTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <p id="text">Served through Cowboy</p>
    """
  end
end
