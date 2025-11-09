defmodule HologramFeatureTests.Navigation.Page5 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Routing.RouteWithPercentEncodedParamsPage

  route "/navigation/page-5"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <h1>Page 5 title</h1>
    <Link to={RouteWithPercentEncodedParamsPage, a: "hello world", b: "foo/bar"}>Link with percent-encoded params</Link>
    """
  end
end
