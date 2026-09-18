defmodule HologramFeatureTests.LiveReload.Page2 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.LiveReload.Page1

  route "/live-reload/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <h1>Live reload page 2</h1>
    <Link to={Page1}>Page 1 link</Link>
    """
  end
end
