defmodule HologramFeatureTests.EmptyPage do
  use Hologram.Page

  route "/empty"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO""
  end
end
