defmodule HologramFeatureTests.Events.OnceTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.OncePage

  feature "fires the action once, then stops re-dispatching", %{session: session} do
    session
    |> visit(OncePage)
    |> click(css("#click_button"))
    |> click(css("#click_button"))
    |> click(css("#click_button"))
    |> assert_text(css("#click_result"), "1")
  end

  feature "stays spent across re-renders but re-arms when the element is re-created",
          %{session: session} do
    session
    |> visit(OncePage)
    |> click(css("#rearm_button"))
    # An unrelated re-render keeps the element in place, so the binding stays spent.
    |> click(css("#rerender_button"))
    |> click(css("#rearm_button"))
    |> assert_text(css("#rearm_result"), "1")
    # Hiding then showing the element re-creates it, which re-arms the binding.
    |> click(css("#toggle_button"))
    |> click(css("#toggle_button"))
    |> click(css("#rearm_button"))
    |> assert_text(css("#rearm_result"), "2")
  end

  feature "fires on the first resize only, then the observer is torn down",
          %{session: session} do
    session
    |> visit(OncePage)
    |> execute_script("""
    document.getElementById('resize_once_box').style.width = '150px';
    document.getElementById('resize_plain_box').style.width = '150px';
    """)
    |> assert_text(css("#resize_plain_result"), "1")
    |> execute_script("""
    document.getElementById('resize_once_box').style.width = '200px';
    document.getElementById('resize_plain_box').style.width = '200px';
    """)
    # The plain binding reaching 2 proves both resizes were processed, so the once binding staying
    # at 1 means the second resize did not fire it.
    |> assert_text(css("#resize_plain_result"), "2")
    |> assert_text(css("#resize_once_result"), "1")
  end

  feature "fires on the first reach only, then the scroll listener is torn down",
          %{session: session} do
    session
    |> visit(OncePage)
    # Scroll both containers to the bottom: the first reach for each.
    |> execute_script("""
    document.getElementById('reach_once_box').scrollTop = 900;
    document.getElementById('reach_witness_box').scrollTop = 900;
    """)
    |> assert_text(css("#reach_bottom_result"), "1")
    # Scroll both back to the top. Waiting for the witness's top reach proves a frame elapsed and
    # the witness's bottom edge-trigger reset, so the next scroll down can re-fire it.
    |> execute_script("""
    document.getElementById('reach_once_box').scrollTop = 0;
    document.getElementById('reach_witness_box').scrollTop = 0;
    """)
    |> assert_text(css("#reach_top_result"), "2")
    # Scroll both to the bottom again. The witness re-fires; the once binding's listener is gone.
    |> execute_script("""
    document.getElementById('reach_once_box').scrollTop = 900;
    document.getElementById('reach_witness_box').scrollTop = 900;
    """)
    # The witness reaching 2 proves a second reach was processed, so the once binding staying at 1
    # means the second reach did not fire it.
    |> assert_text(css("#reach_bottom_result"), "2")
    |> assert_text(css("#reach_once_result"), "1")
  end
end
