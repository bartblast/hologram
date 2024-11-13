defmodule HologramFeatureTests.Navigation4Page do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Navigation2Page, as: Page2

  route "/navigation-4"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~H"""
    <h1>Page 4 title</h1>
    <div style="width: 10000px; height: 500px; background-color: blue"></div>
    <Link to={Page2} style="margin-left: 500px">Page 2 link</Link>
    <a href="https://www.wikipedia.org/">Wikipedia</a>
    <div style="width: 10000px; height: 10000px; background-color: blue"></div>
    """
  end
end