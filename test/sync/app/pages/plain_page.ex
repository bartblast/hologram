defmodule HologramSyncTests.PlainPage do
  use Hologram.Page

  route "/plain"

  layout HologramSyncTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <p>Plain</p>
    """
  end
end
