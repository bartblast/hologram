defmodule HologramFeatureTests.Middleware.Page2 do
  use Hologram.Page

  route "/middleware/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def middleware(server) do
    put_redirect(server, HologramFeatureTests.Middleware.Page3)
  end

  def template do
    ~HOLO"""
    <h1>Middleware / Page 2</h1>
    """
  end
end
