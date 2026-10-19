defmodule HologramFeatureTests.Events.ReachTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.ReachPage

  describe "$reach_bottom" do
    feature "fires on mount when the content does not fill the container", %{session: session} do
      session
      |> visit(ReachPage)
      |> assert_text(css("#filled_bottom_result"), "1")
    end

    feature "fires before the edge is visible but inside the within() distance", %{
      session: session
    } do
      # The container is 100px tall with 1000px of content. At scrollTop 780 the bottom edge is still
      # 120px below the fold (1000 - 780 - 100), inside the 200px within() distance, so the reach
      # fires before the edge is scrolled into view.
      session
      |> visit(ReachPage)
      |> execute_script("document.getElementById('scrollable_vertical').scrollTop = 780;")
      |> assert_text(css("#scroll_bottom_result"), "1")
    end

    feature "fires when scrolled to the bottom past a hidden last child", %{session: session} do
      # A detector that watched the container's last element would miss this: a display:none child
      # is boxless, so it never intersects and reports an all-zero rect. Scroll-offset reads the
      # container's own scroll metrics, so a hidden last child cannot suppress the event.
      session
      |> visit(ReachPage)
      |> execute_script("document.getElementById('hidden_child_vertical').scrollTop = 900;")
      |> assert_text(css("#hidden_child_bottom_result"), "1")
    end

    feature "fires for a reach container nested inside a component", %{session: session} do
      # A wiring scheme that only reaches the page's top-level elements, or that skips re-wiring
      # after a patch, would miss a reach container living inside a child component. Hologram
      # re-resolves reach bindings from the patched DOM on every render at any depth, so a nested
      # container is wired like any other.
      session
      |> visit(ReachPage)
      |> assert_text(css("#nested_bottom_result"), "1")
    end

    feature "does not fire early when a tall edge child appears before the true edge", %{
      session: session
    } do
      # The last child is 400px tall, so it enters the 100px viewport ~520px before the container's
      # true bottom. A detector tied to that child's geometry would fire as soon as it appears, far
      # outside within(200px). Scroll-offset measures the distance to the real edge: at scrollTop 600
      # the tall child is in view but the edge is still 320px away, so it must not fire. Scrolling a
      # different container to its edge is the sync point that proves a frame elapsed before checking.
      session
      |> visit(ReachPage)
      |> execute_script("document.getElementById('tall_child_vertical').scrollTop = 600;")
      |> execute_script("document.getElementById('scrollable_vertical').scrollTop = 1000;")
      |> assert_text(css("#scroll_bottom_result"), "1")
      |> assert_text(css("#tall_child_bottom_result"), "0")
      |> execute_script("document.getElementById('tall_child_vertical').scrollTop = 850;")
      |> assert_text(css("#tall_child_bottom_result"), "1")
    end

    feature "fires when a resize brings the edge into range without a scroll", %{session: session} do
      # The container starts more than one viewport (its default within) from the bottom, so it does
      # not fire on mount. Shrinking a child - no scroll, no re-render - brings the bottom edge within
      # range, and the resize watch on the container's children is the only thing that can fire here:
      # a detector wired only to scroll events would stay silent while the content moves under it.
      session
      |> visit(ReachPage)
      |> assert_text(css("#resize_bottom_result"), "0")
      |> execute_script("document.getElementById('resize_spacer').style.height = '100px';")
      |> assert_text(css("#resize_bottom_result"), "1")
    end

    feature "fires on mount in a column-reverse container, which starts at its bottom", %{
      session: session
    } do
      # The browser opens a column-reverse container at its content start, the visual bottom, and
      # reports scrollTop 0 there. Read as a distance from the top, that position would put the
      # bottom edge 900px away (the content height minus the viewport) and keep it silent.
      session
      |> visit(ReachPage)
      |> assert_text(css("#reversed_bottom_result"), "1")
    end

    feature "fires again when a column-reverse container is scrolled back down to it", %{
      session: session
    } do
      # scrollTop runs from -900 at the visual top to 0 at the visual bottom. Setting -1000 clamps
      # to the visual top.
      session
      |> visit(ReachPage)
      |> assert_text(css("#reversed_bottom_result"), "1")
      |> execute_script("document.getElementById('reversed_vertical').scrollTop = -1000;")
      # Wait for the top edge to fire first: that proves the container scrolled off the bottom edge,
      # resetting its edge-trigger so scrolling back down re-fires it.
      |> assert_text(css("#reversed_top_result"), "1")
      |> execute_script("document.getElementById('reversed_vertical').scrollTop = 0;")
      |> assert_text(css("#reversed_bottom_result"), "2")
    end
  end

  describe "$reach_left" do
    feature "fires on mount when the edge is already in view", %{session: session} do
      session
      |> visit(ReachPage)
      |> assert_text(css("#scroll_left_result"), "1")
    end

    feature "fires again when the container is scrolled back to it", %{session: session} do
      session
      |> visit(ReachPage)
      |> assert_text(css("#scroll_left_result"), "1")
      |> execute_script("document.getElementById('scrollable_horizontal').scrollLeft = 900;")
      # Wait for the right edge to fire first: that proves the container scrolled off the left edge,
      # resetting its edge-trigger so scrolling back re-fires it.
      |> assert_text(css("#scroll_right_result"), "1")
      |> execute_script("document.getElementById('scrollable_horizontal').scrollLeft = 0;")
      |> assert_text(css("#scroll_left_result"), "2")
    end

    feature "does not fire on mount in a right-to-left container, which starts at its right edge",
            %{session: session} do
      # The browser opens a right-to-left container at its right edge and reports scrollLeft 0
      # there, 900px from the left edge. Read as a distance from the left, that 0 would fire the
      # left edge. Waiting for the right edge proves the mount check ran.
      session
      |> visit(ReachPage)
      |> assert_text(css("#rtl_right_result"), "1")
      |> assert_text(css("#rtl_left_result"), "0")
    end

    feature "fires when a right-to-left container is scrolled to its left edge", %{
      session: session
    } do
      # scrollLeft runs from -900 at the left edge to 0 at the right edge. Setting -1000 clamps to
      # the left edge. Waiting for the right edge proves the mount check ran, so the left edge's
      # count can only come from the scroll.
      session
      |> visit(ReachPage)
      |> assert_text(css("#rtl_right_result"), "1")
      |> assert_text(css("#rtl_left_result"), "0")
      |> execute_script("document.getElementById('rtl_horizontal').scrollLeft = -1000;")
      |> assert_text(css("#rtl_left_result"), "1")
    end
  end

  describe "$reach_right" do
    feature "fires on mount when the content does not fill the container", %{session: session} do
      session
      |> visit(ReachPage)
      |> assert_text(css("#filled_right_result"), "1")
    end

    feature "fires when the container is scrolled right to it", %{session: session} do
      session
      |> visit(ReachPage)
      |> execute_script("document.getElementById('scrollable_horizontal').scrollLeft = 900;")
      |> assert_text(css("#scroll_right_result"), "1")
    end

    feature "fires on mount in a right-to-left container, which starts at its right edge", %{
      session: session
    } do
      session
      |> visit(ReachPage)
      |> assert_text(css("#rtl_right_result"), "1")
    end
  end

  describe "$reach_top" do
    feature "fires on mount when the edge is already in view", %{session: session} do
      session
      |> visit(ReachPage)
      |> assert_text(css("#scroll_top_result"), "1")
    end

    feature "fires again when the container is scrolled back up to it", %{session: session} do
      session
      |> visit(ReachPage)
      |> assert_text(css("#scroll_top_result"), "1")
      |> execute_script("document.getElementById('scrollable_vertical').scrollTop = 900;")
      # Wait for the bottom edge to fire first: that proves the container scrolled off the top edge,
      # resetting its edge-trigger so scrolling back up re-fires it.
      |> assert_text(css("#scroll_bottom_result"), "1")
      |> execute_script("document.getElementById('scrollable_vertical').scrollTop = 0;")
      |> assert_text(css("#scroll_top_result"), "2")
    end

    feature "does not fire on mount in a column-reverse container, which starts at its bottom", %{
      session: session
    } do
      # The browser opens a column-reverse container at its visual bottom and reports scrollTop 0
      # there, 900px from the top. Read as a distance from the top, that 0 would fire the top edge.
      # Waiting for the bottom edge proves the mount check ran.
      session
      |> visit(ReachPage)
      |> assert_text(css("#reversed_bottom_result"), "1")
      |> assert_text(css("#reversed_top_result"), "0")
    end

    feature "fires each time a column-reverse container is scrolled up to its visual top", %{
      session: session
    } do
      # Waiting for the bottom edge's mount fire proves the mount check ran before the first scroll,
      # so the top edge's count can only come from the scrolls.
      session
      |> visit(ReachPage)
      |> assert_text(css("#reversed_bottom_result"), "1")
      |> assert_text(css("#reversed_top_result"), "0")
      |> execute_script("document.getElementById('reversed_vertical').scrollTop = -1000;")
      |> assert_text(css("#reversed_top_result"), "1")
      |> execute_script("document.getElementById('reversed_vertical').scrollTop = 0;")
      # Wait for the bottom edge to fire again: that proves the container scrolled off the top edge,
      # resetting its edge-trigger so scrolling back up re-fires it.
      |> assert_text(css("#reversed_bottom_result"), "2")
      |> execute_script("document.getElementById('reversed_vertical').scrollTop = -1000;")
      |> assert_text(css("#reversed_top_result"), "2")
    end

    feature "loads older items above a column-reverse list without moving the view", %{
      session: session
    } do
      # The list holds 20 items of 50px, newest first, in a 100px box that opens at its visual
      # bottom. Each load appends 10 older items to the end of the list, which is the visual top.
      # The browser measures the scroll position from the bottom, so content added above leaves it
      # unchanged. The diff patches the first 20 nodes in place and appends the new ones, so the
      # oldest item loaded so far stays at the top of the view while the top edge ends up 500px
      # away, ready to fire again.
      message_31_offset = """
      const container = document.getElementById('chat_vertical');
      const message = Array.from(container.children)
        .find((child) => child.textContent === 'Message 31');
      return message.getBoundingClientRect().top - container.getBoundingClientRect().top;
      """

      session
      |> visit(ReachPage)
      |> assert_script_result("return document.getElementById('chat_vertical').scrollTop;", 0)
      |> execute_script("document.getElementById('chat_vertical').scrollTop = -1000;")
      |> assert_text(css("#chat_loads_result"), "1")
      |> assert_script_result(
        "return document.getElementById('chat_vertical').scrollHeight;",
        1500
      )
      |> assert_script_result("return document.getElementById('chat_vertical').scrollTop;", -900)
      |> assert_script_result(message_31_offset, 0)
      |> execute_script("document.getElementById('chat_vertical').scrollTop = -2000;")
      |> assert_text(css("#chat_loads_result"), "2")
      |> assert_script_result(
        "return document.getElementById('chat_vertical').scrollHeight;",
        2000
      )
    end
  end
end
