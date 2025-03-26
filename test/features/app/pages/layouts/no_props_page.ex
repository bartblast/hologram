defmodule HologramFeatureTests.Layouts.NoPropsPage do
  use Hologram.Page

  route "/layouts/no-props"

  layout HologramFeatureTests.Components.LayoutWithoutProps

  def template do
    ~HOLO""
  end
end
