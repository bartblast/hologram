defmodule HologramFeatureTests.NavigationTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Navigation1Page, as: Page1
  alias HologramFeatureTests.Navigation2Page, as: Page2
  alias HologramFeatureTests.Navigation3Page, as: Page3

  test "link component, without params", %{session: session} do
    session
    |> visit(Page1)
    |> click(link("Page 2 link"))
    |> assert_page(Page2)
    |> assert_text("Page 2 title")
    |> click(button("Put page 2 result"))
    |> assert_text("Page 2 result")
  end

  test "link component, with params", %{session: session} do
    session
    |> visit(Page1)
    |> click(link("Page 3 link"))
    |> assert_page(Page3, s: "abc", i: "123")
    |> assert_text("Page 3 title")
    |> assert_text(~s/%{i: 123, s: "abc"}/)
    |> click(button("Put page 3 result"))
    |> assert_text("Page 3 result")
  end

  # test "go back", %{session: session} do
  #   session
  #   |> visit(Page1)
  #   |> click(link("Page 2 link"))
  #   |> assert_page(Page2)
  #   |> go_back()
  #   |> assert_page(Page1)
  #   |> assert_text("Page 1 title")
  #   |> click(button("Put page 1 result"))
  #   |> assert_text("Page 1 result")
  # end

  # test "go back after reload", %{session: session} do
  #   session
  #   |> visit(Page1)
  #   |> click(link("Page 2 link"))
  #   |> assert_page(Page2)
  #   |> reload()
  #   |> assert_page(Page2)
  #   |> go_back()
  #   |> assert_page(Page1)
  #   |> assert_text("Page 1 title")
  #   |> click(button("Put page 1 result"))
  #   |> assert_text("Page 1 result")
  # end

  # test "go forward", %{session: session} do
  #   session
  #   |> visit(Page1)
  #   |> click(link("Page 2 link"))
  #   |> assert_page(Page2)
  #   |> go_back()
  #   |> assert_page(Page1)
  #   |> go_forward()
  #   |> assert_page(Page2)
  #   |> assert_text("Page 2 title")
  #   |> click(button("Put page 2 result"))
  #   |> assert_text("Page 2 result")
  # end

  # test "go forward after reload", %{session: session} do
  #   session
  #   |> visit(Page1)
  #   |> click(link("Page 2 link"))
  #   |> assert_page(Page2)
  #   |> go_back()
  #   |> assert_page(Page1)
  #   |> reload()
  #   |> assert_page(Page1)
  #   |> go_forward()
  #   |> assert_page(Page2)
  #   |> assert_text("Page 2 title")
  #   |> click(button("Put page 2 result"))
  #   |> assert_text("Page 2 result")
  # end

  test "put page in action", %{session: session} do
    session
    |> visit(Page1)
    |> click(button("Change page"))
    |> assert_page(Page2)
    |> assert_text("Page 2 title")
    |> click(button("Put page 2 result"))
    |> assert_text("Page 2 result")
  end
end
