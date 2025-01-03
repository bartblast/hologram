defmodule HologramFeatureTests.RenderingTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Rendering.Page1

  feature "root element without attributes", %{session: session} do
    session
    |> visit(Page1)
    |> assert_has(css("html"))
  end
end
