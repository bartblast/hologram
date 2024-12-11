defmodule HologramFeatureTests.Pages.LayoutGettingPropsImplicitelyPage do
  use Hologram.Page

  route "/pages/layout-getting-props-implicitely"

  layout HologramFeatureTests.Components.LayoutWithProps

  def init(_params, component, _server) do
    put_state(component, a: "abc", b: 123, c: :xyz)
  end

  def template do
    ~H""
  end
end
