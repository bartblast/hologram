defmodule HologramFeatureTests.Navigation.Page6 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Navigation.Page7

  route "/navigation/6"

  layout HologramFeatureTests.Components.NavigationLayout

  def template do
    ~HOLO"""
    <h1>Page 6 title</h1>
    <Link to={Page7}>Page 7 link</Link>
    """
  end
end
