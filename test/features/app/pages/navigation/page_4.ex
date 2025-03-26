defmodule HologramFeatureTests.Navigation.Page4 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Navigation.Page2

  route "/navigation/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <h1>Page 4 title</h1>
    <div style="width: 10000px; height: 500px; background-color: blue"></div>
    <Link to={Page2} style="margin-left: 500px">Page 2 link</Link>
    <a href="https://example.com/">External link</a>
    <div style="width: 10000px; height: 10000px; background-color: blue"></div>
    """
  end
end
