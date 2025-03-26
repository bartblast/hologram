defmodule HologramFeatureTests.Layouts.PropsPassedImplicitelyPage do
  use Hologram.Page

  route "/layouts/props-passed-implicitely"

  layout HologramFeatureTests.Components.LayoutWithProps

  def init(_params, component, _server) do
    put_state(component, a: "abc", b: 123, c: :xyz)
  end

  def template do
    ~HOLO""
  end
end
