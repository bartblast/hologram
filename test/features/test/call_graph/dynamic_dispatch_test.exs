defmodule HologramFeatureTests.DynamicDispatchTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.DynamicDispatchPage

  feature "Date.new/3", %{session: session} do
    expected = "{:ok, %{__struct__: Date, calendar: Calendar.ISO, day: 15, month: 6, year: 2024}}"

    session
    |> visit(DynamicDispatchPage)
    |> click(button("Date.new"))
    |> assert_text(css("#result"), expected)
  end
end
