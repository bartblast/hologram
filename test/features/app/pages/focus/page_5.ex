defmodule HologramFeatureTests.Focus.Page5 do
  use Hologram.Page

  route "/focus/5"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <h1>Page 5 title</h1>
    <p>
      <input type="text" id="page_5_search" $focused={true} />
    </p>
    """
  end
end
