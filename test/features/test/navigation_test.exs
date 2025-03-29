defmodule HologramFeatureTests.NavigationTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Navigation.Page1
  alias HologramFeatureTests.Navigation.Page2
  alias HologramFeatureTests.Navigation.Page3
  alias HologramFeatureTests.Navigation.Page4

  describe "link component" do
    feature "without params", %{session: session} do
      session
      |> visit(Page1)
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> assert_text("Page 2 title")
      |> click(button("Put page 2 result A"))
      |> assert_text("Page 2 result A")
    end

    feature "with params", %{session: session} do
      session
      |> visit(Page1)
      |> click(link("Page 3 link"))
      |> assert_page(Page3, s: "abc", i: "123")
      |> assert_text("Page 3 title")
      |> assert_text(~s/%{i: 123, s: "abc"}/)
      |> click(button("Put page 3 result"))
      |> assert_text("Page 3 result")
    end
  end

  describe "history" do
    feature "go back", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> go_back()
      |> assert_page(Page1)
      |> assert_text("Page 1 title")
      |> assert_text("Page 1 result A")
      |> click(button("Put page 1 result B"))
      |> assert_text("Page 1 result B")
    end

    feature "go back after reload", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> reload()
      |> assert_page(Page2)
      |> go_back()
      |> assert_page(Page1)
      |> assert_text("Page 1 title")
      |> assert_text("Page 1 result A")
      |> click(button("Put page 1 result B"))
      |> assert_text("Page 1 result B")
    end

    feature "go back to Hologram page (from non-Hologram page)", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> assert_text("Page 1 result A")
      |> click(link("External link"))
      |> assert_text("Example Domain")
      |> go_back()
      |> assert_page(Page1)
      |> assert_text("Page 1 title")
      |> assert_text("Page 1 result A")
      |> click(button("Put page 1 result B"))
      |> assert_text("Page 1 result B")
    end

    feature "go forward", %{session: session} do
      session
      |> visit(Page1)
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> click(button("Put page 2 result A"))
      |> go_back()
      |> assert_page(Page1)
      |> go_forward()
      |> assert_page(Page2)
      |> assert_text("Page 2 title")
      |> assert_text("Page 2 result A")
      |> click(button("Put page 2 result B"))
      |> assert_text("Page 2 result B")
    end

    feature "go forward after reload", %{session: session} do
      session
      |> visit(Page1)
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> click(button("Put page 2 result A"))
      |> go_back()
      |> assert_page(Page1)
      |> reload()
      |> assert_page(Page1)
      |> go_forward()
      |> assert_page(Page2)
      |> assert_text("Page 2 title")
      |> assert_text("Page 2 result A")
      |> click(button("Put page 2 result B"))
      |> assert_text("Page 2 result B")
    end

    feature "go forward to Hologram page (from non-Hologram page)", %{session: session} do
      session
      |> visit("https://example.com/")
      |> assert_text("Example Domain")
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> assert_text("Page 1 result A")
      |> go_back()
      |> assert_text("Example Domain")
      |> go_forward()
      |> assert_page(Page1)
      |> assert_text("Page 1 title")
      |> assert_text("Page 1 result A")
      |> click(button("Put page 1 result B"))
      |> assert_text("Page 1 result B")
    end
  end

  feature "put page in action", %{session: session} do
    session
    |> visit(Page1)
    |> click(button("Change page"))
    |> assert_page(Page2)
    |> assert_text("Page 2 title")
    |> click(button("Put page 2 result A"))
    |> assert_text("Page 2 result A")
  end

  describe "scroll position" do
    feature "when navigating to a new page", %{session: session} do
      session
      |> visit(Page4)
      |> scroll_to(10, 20)
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> assert_scroll_position(0, 0)
    end

    feature "when using history navigation without reload, within Hologram app", %{
      session: session
    } do
      session
      |> visit(Page4)
      |> scroll_to(10, 20)
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> go_back()
      |> assert_page(Page4)
      |> assert_scroll_position(10, 20)
    end

    feature "when using history navigation with reload, within Hologram app", %{session: session} do
      session
      |> visit(Page4)
      |> scroll_to(10, 20)
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> reload()
      |> assert_page(Page2)
      |> go_back()
      |> assert_page(Page4)
      |> assert_scroll_position(10, 20)
    end

    feature "when using history navigation coming from non-Hologram page", %{session: session} do
      session
      |> visit(Page4)
      |> scroll_to(10, 20)
      |> click(link("External link"))
      |> assert_text("Example Domain")
      |> go_back()
      |> assert_page(Page4)
      |> assert_scroll_position(10, 20)
    end
  end
end
