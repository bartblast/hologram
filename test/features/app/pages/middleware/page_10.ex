defmodule HologramFeatureTests.Middleware.Page10 do
  use Hologram.Page

  alias HologramFeatureTests.Middleware.Page2

  route "/middleware/10"

  layout HologramFeatureTests.Components.DefaultLayout

  # Redirects to a page that redirects again, so a navigation here takes two hops before it lands.
  middleware :redirect

  def redirect(server, _opts) do
    put_redirect(server, Page2)
  end

  def template do
    ~HOLO"""
    <h1>Middleware / Page 10</h1>
    """
  end
end
