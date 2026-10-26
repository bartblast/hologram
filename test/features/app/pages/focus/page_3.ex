defmodule HologramFeatureTests.Focus.Page3 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Focus.Page4
  alias HologramFeatureTests.Focus.Page5

  route "/focus/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <h1>Page 3 title</h1>
    <p>
      <input type="text" id="page_3_search" $focused={true} />
      <input type="text" id="page_3_other" />
    </p>
    <p>
      <Link to={Page4}>Page 4 link</Link>
      <Link to={Page5}>Page 5 link</Link>
    </p>
    """
  end
end
