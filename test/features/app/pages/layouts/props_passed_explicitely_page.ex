defmodule HologramFeatureTests.Layouts.PropsPassedExplicitelyPage do
  use Hologram.Page

  route "/layouts/props-passed-explicitely"

  layout HologramFeatureTests.Components.LayoutWithProps, a: "abc", b: 123, c: :xyz

  def template do
    ~HOLO""
  end
end
