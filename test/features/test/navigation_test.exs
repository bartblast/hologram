defmodule HologramFeatureTests.NavigationTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Navigation1Page, as: Page1
  alias HologramFeatureTests.Navigation2Page, as: Page2

  test "link", %{session: session} do
    session
    |> visit(Page1)
    |> click(link("Page 2 link"))
    |> assert_page(Page2)
    |> assert_text("Page 2 title")
    |> click(button("Put page 2 result"))
    |> assert_text("Page 2 result")
  end
end
