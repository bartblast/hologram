defmodule HologramFeatureTests.RenderingTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Rendering.Page1
  alias HologramFeatureTests.Rendering.Page2
  alias HologramFeatureTests.Rendering.Page3

  feature "root element without attributes", %{session: session} do
    session
    |> visit(Page1)
    |> assert_has(css("html"))
  end

  feature "root element with single attribute", %{session: session} do
    session
    |> visit(Page2)
    |> assert_has(css("html[attr_1='value_1']"))
  end

  feature "root element with multiple attributes", %{session: session} do
    session
    |> visit(Page3)
    |> assert_has(css("html[attr_1='value_1']"))
    |> assert_has(css("html[attr_2='value_2']"))
  end
end
