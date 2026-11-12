defmodule HologramFeatureTests.Derived.Page1 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Derived.Component1

  route "/derived/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component1 cid="component_1" excluded_title="bravo" />
    """
  end
end
