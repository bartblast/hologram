defmodule HologramFeatureTests.ResponseHeaders.Page3 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.ResponseHeaders.Page1
  alias HologramFeatureTests.ResponseHeaders.Page2

  route "/response-headers/3"

  layout HologramFeatureTests.Components.ResponseHeadersLayout

  def template do
    ~HOLO"""
    <h1>Response Headers / Page 3</h1>

    <Link to={Page1}>Page 1 link</Link>
    <Link to={Page2}>Page 2 link</Link>

    <p id="result">navigation origin</p>
    """
  end
end
