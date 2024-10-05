defmodule HologramFeatureTests.NavigationTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Navigation1Page, as: Page1
  alias HologramFeatureTests.Navigation2Page, as: Page2

  test "link component", %{session: session} do
    session
    |> visit(Page1)
    |> click(link("Page 2 link"))
    |> assert_page(Page2)
    |> assert_text("Page 2 title")
    |> click(button("Put page 2 result"))
    |> assert_text("Page 2 result")
  end

  test "go back", %{session: session} do
    session
    |> visit(Page1)
    |> click(link("Page 2 link"))
    |> assert_page(Page2)
    |> go_back()
    |> assert_page(Page1)
    |> assert_text("Page 1 title")
    |> click(button("Put page 1 resultgs"))
    |> assert_text("Page 1 result")
  end
end
