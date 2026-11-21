defmodule HologramFeatureTests.Derived.Page5 do
  use Hologram.Page

  alias HologramFeatureTests.Components.Derived.Component3

  route "/derived/5"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <Component3 cid="built_queries" excluded_titles={["bravo", "delta"]} />
    """
  end
end
