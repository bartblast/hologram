defmodule HologramFeatureTests.Events.AllowDefault.Page2 do
  use Hologram.Page

  route "/events/allow-default/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
  end

  def template do
    ~HOLO"""
    <p id="target">Allow default target page</p>
    """
  end
end
