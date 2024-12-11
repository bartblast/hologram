defmodule HologramFeatureTests.Pages.LayoutGettingPropsExplicitelyPage do
  use Hologram.Page

  route "/pages/layout-getting-props-explicitely"

  layout HologramFeatureTests.Components.LayoutWithProps, a: "abc", b: 123, c: :xyz

  def template do
    ~H""
  end
end
