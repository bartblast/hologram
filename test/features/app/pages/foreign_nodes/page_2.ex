defmodule HologramFeatureTests.ForeignNodes.Page2 do
  use Hologram.Page

  route "/foreign-nodes/2"

  layout HologramFeatureTests.Components.ForeignNodesLayout

  def template do
    ~HOLO"""
    <h1>Foreign nodes page 2</h1>
    """
  end
end
