defmodule HologramFeatureTests.Events.ReachTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.ReachPage

  describe "$reach_bottom" do
    feature "fires on mount when the content does not fill the container", %{session: session} do
      session
      |> visit(ReachPage)
      |> assert_text(css("#filled_bottom_result"), "1")
    end

    feature "fires within the prefetch distance before the edge is visible", %{session: session} do
      # The container is 100px tall and its bottom child sits at 980-1000px, so at scrollTop 780
      # (visible 780-880) the child is below the fold but inside the 200px within() prefetch.
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
      # Wait for the right edge so the observer has registered the left edge leaving view.
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
      # Wait for the bottom edge so the observer has registered the top edge leaving view.
      |> assert_text(css("#scroll_bottom_result"), "1")
      |> execute_script("document.getElementById('scrollable_vertical').scrollTop = 0;")
      |> assert_text(css("#scroll_top_result"), "2")
    end
  end
end
