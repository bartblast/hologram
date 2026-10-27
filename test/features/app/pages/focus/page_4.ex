defmodule HologramFeatureTests.Focus.Page4 do
  use Hologram.Page

  route "/focus/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <h1>Page 4 title</h1>
    <p>
      <input type="text" id="page_4_search" autofocus />
      <input type="text" id="page_4_name" />
    </p>
    """
  end
end
