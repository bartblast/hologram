defmodule HologramMinimalTests.HomePage do
  use Hologram.Page

  route "/"

  layout HologramMinimalTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <p>Hello world</p>
    """
  end
end
