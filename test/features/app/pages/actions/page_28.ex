defmodule HologramFeatureTests.Actions.Page28 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Actions.Component23

  route "/actions/28"

  layout HologramFeatureTests.Components.DefaultLayout

  # Hosts an owner and its in-place editor, two components that show the same value.
  def template do
    ~HOLO"""
    <h1>Page 28 title</h1>
    <Component23 cid="component_23" />
    """
  end
end
