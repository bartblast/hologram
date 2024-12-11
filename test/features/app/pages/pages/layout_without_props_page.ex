defmodule HologramFeatureTests.Pages.LayoutWithoutPropsPage do
  use Hologram.Page

  route "/pages/layout-without-props"

  layout HologramFeatureTests.Components.LayoutWithoutProps

  def template do
    ~H""
  end
end
