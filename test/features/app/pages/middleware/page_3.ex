defmodule HologramFeatureTests.Middleware.Page3 do
  use Hologram.Page

  route "/middleware/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <h1>Middleware / Page 3</h1>

    <p id="result">redirect target reached</p>
    """
  end
end
