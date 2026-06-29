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
  end
end
