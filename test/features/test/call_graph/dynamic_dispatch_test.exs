defmodule HologramFeatureTests.DynamicDispatchTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.DynamicDispatchPage

  feature "Date.new/3", %{session: session} do
    session
    |> visit(DynamicDispatchPage)
    |> click(button("Date.new"))
    |> assert_text(css("#result"), "{:ok, ~D[2024-06-15]}")
  end
end
