defmodule HologramEcosystemTests.PlainPage do
  use Hologram.Page

  route "/plain"

  layout HologramEcosystemTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <p id="text">Served with the ecosystem libraries</p>
    """
  end
end
