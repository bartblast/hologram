defmodule HologramFeatureTests.NavigationTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Navigation.Page1
  alias HologramFeatureTests.Navigation.Page2
  alias HologramFeatureTests.Navigation.Page3
  alias HologramFeatureTests.Navigation.Page4
  alias HologramFeatureTests.Navigation.Page5
  alias HologramFeatureTests.Navigation.Page6
  alias HologramFeatureTests.Navigation.Page7
  alias HologramFeatureTests.Navigation.Page8
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

  describe "navigation to the current page" do
    # A page the browser already holds is fetched and patched like any other - the marker
    # survives, which a document load would have cleared.
    feature "patches the page instead of loading it", %{session: session} do
      session = visit(session, Page1)

      execute_script(session, "window.__hologramNavigationMarker__ = 'kept';")

      session
      |> click(link("Page 1 link"))
      |> assert_page(Page1)

      assert script_result(session, "return window.__hologramNavigationMarker__;") == "kept"
    end

    feature "remounts the page put by an action", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> assert_text("Page 1 result A")
      |> click(button("Put current page"))
      |> assert_page(Page1)
      |> assert_text("Page result: nil")
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

  describe "hydration state beside the render" do
    # A navigated page used to be handed its mount data as a script the patch inserted and the
    # browser then ran; it now arrives as payload fields. The click is what proves the state got
    # through: it can only change what is on screen if the component registry was populated, and
    # the registry is what the mount data carries.
    #
    # The document cannot show the difference on its own. A mount data script is transient on both
    # paths - the page's own render sets page_mounted?, so the patch that follows the mount removes
    # it - which is why the absence is also asserted where it is deterministic: the tree the
    # controller sends holds no such script (controller_test.exs), and the component renders none
    # off the initial page (ui/runtime_test.exs).
    feature "a navigated page hydrates without a mount data script", %{session: session} do
      no_mount_data_script =
        ~s|return [...document.querySelectorAll("script")].every((s) => !s.textContent.includes("pageMountData"));|

      session
      |> visit(Page1)
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> assert_text("Page 2 title")
      |> assert_script_result(no_mount_data_script, true)
      |> click(button("Put page 2 result A"))
      |> assert_text("Page 2 result A")
      |> assert_script_result(no_mount_data_script, true)
    end
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

    feature "navigation to the current page resets component state", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Put page 1 result A"))
      |> assert_text("Page 1 result A")
      |> click(link("Page 1 link"))
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

  describe "layout state across navigation" do
    # The layout's nodes are the same on both pages, so a navigation must leave them alone: the
    # container's scroll position lives only in its DOM node and would not survive a rebuild.
    # The click on the new page proves the mount completed on those same adopted nodes.
    feature "a scrolled layout container holds its place", %{session: session} do
      scroll = ~s|document.getElementById("shell").scrollTop = 30;|
      scroll_top = ~s|return document.getElementById("shell").scrollTop;|

      session = visit(session, Page6)

      script_result(session, scroll)

      session
      |> assert_script_result(scroll_top, 30)
      |> click(link("Page 7 link"))
      |> assert_page(Page7)
      |> assert_text("Page 7 title")
      |> assert_script_result(scroll_top, 30)
      |> click(button("Put page 7 result"))
      |> assert_text("Page 7 result")
      |> assert_script_result(scroll_top, 30)
    end
  end

  describe "navigation to a page whose code is already loaded" do
    # A page's bundle is keyed by the source it loads, so a navigation landing back on it adopts
    # that script rather than creating it, and an adopted script never runs again to announce
    # itself. Nothing would mount if the mount waited to be announced.
    #
    # The rendered param alone would not catch that: the patch draws it either way. The click is
    # what needs a mount to have happened, and what it reports is the param the mount ran with.
    feature "mounts without the page's bundle announcing itself", %{session: session} do
      session
      |> visit(Page8, n: 1)
      |> assert_text(css("#param_n"), "1")
      |> click(link("Page 8 next link"))
      |> assert_page(Page8, n: 2)
      |> assert_text(css("#param_n"), "2")
      |> click(button("Put page 8 result"))
      |> assert_text(css("#page_result"), "2")
    end
  end
end
