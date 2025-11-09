defmodule HologramFeatureTests.NavigationTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Navigation.Page1
  alias HologramFeatureTests.Navigation.Page2
  alias HologramFeatureTests.Navigation.Page3
  alias HologramFeatureTests.Navigation.Page4
  alias HologramFeatureTests.Navigation.Page5
  alias HologramFeatureTests.Routing.RouteWithPercentEncodedParamsPage

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
      |> assert_text(~s'%{i: 123, s: "abc"}')
      |> click(button("Put page 3 result"))
      |> assert_text("Page 3 result")
    end

    feature "with percent-encoded params", %{session: session} do
      session
      |> visit(Page5)
      |> click(link("Link with percent-encoded params"))
      |> assert_page(RouteWithPercentEncodedParamsPage, a: "hello world", b: "foo/bar")
      |> assert_text("Route With Percent Encoded Params Page")
      |> assert_text(css("#param_a"), ~s'"hello world"')
      |> assert_text(css("#param_b"), ~s'"foo/bar"')
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
      |> assert_text("External Page")
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
      |> visit("/external")
      |> assert_text("External Page")
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> assert_text("Page 1 result A")
      |> go_back()
      |> assert_text("External Page")
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

  describe "component state management" do
    feature "page reload resets component state", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> assert_text("Page 1 result A")
      |> reload()
      |> assert_page(Page1)
      |> assert_text("Page result: nil")
    end

    feature "back navigation preserves component state", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> assert_text("Page 1 result A")
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> go_back()
      |> assert_page(Page1)
      |> assert_text("Page 1 result A")
    end

    feature "forward navigation preserves component state", %{session: session} do
      session
      |> visit(Page1)
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> click(button("Put page 2 result A"))
      |> assert_text("Page 2 result A")
      |> go_back()
      |> assert_page(Page1)
      |> go_forward()
      |> assert_page(Page2)
      |> assert_text("Page 2 result A")
    end

    feature "page reload after navigation resets component state", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> assert_text("Page 1 result A")
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> click(button("Put page 2 result A"))
      |> assert_text("Page 2 result A")
      |> reload()
      |> assert_page(Page2)
      # Reloaded page state should be reset after reload
      |> assert_text("Page result: nil")
      |> go_back()
      |> assert_page(Page1)
      # Previous page state should still be preserved
      |> assert_text("Page 1 result A")
    end
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
      |> assert_text("External Page")
      |> go_back()
      |> assert_page(Page4)
      |> assert_scroll_position(10, 20)
    end
  end
end
