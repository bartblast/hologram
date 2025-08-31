defmodule HologramFeatureTests.Actions.Page4 do
  use Hologram.Page
  alias HologramFeatureTests.Components.Actions.Component2

  route "/actions/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component2 cid="component_2" />
    """
  end
end
