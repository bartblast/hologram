defmodule HologramFeatureTests.LiveReload.Page3 do
  use Hologram.Page

  route "/live-reload/3"

  layout HologramFeatureTests.Components.LiveReloadLayout

  def template do
    ~HOLO"""
    <h1>Live reload page 3</h1>
    <p id="styled">Styled text</p>
    """
  end
end
