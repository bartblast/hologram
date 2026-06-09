defmodule HologramFeatureTests.Events.ResizeTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.ResizePage

  feature "the resize event payload carries an element's box sizes", %{session: session} do
    session = visit(session, ResizePage)

    # The div is box-sizing: border-box with 10px padding and a 5px border, so resizing the border
    # box to 300 x 150 leaves a 270 x 120 content box. device_pixel_content_box_size is the content
    # box in device pixels, so it scales by the (read-back) device pixel ratio.
    dpr = script_result(session, "return window.devicePixelRatio;")

    expected =
      inspect(%{
        border_box_size: %{block_size: 150.0, inline_size: 300.0},
        content_box_size: %{block_size: 120.0, inline_size: 270.0},
        device_pixel_content_box_size: %{
          block_size: 120.0 * dpr,
          inline_size: 270.0 * dpr
        }
      })

    session
    |> execute_script("""
    const el = document.getElementById('resizable');
    el.style.width = '300px';
    el.style.height = '150px';
    """)
    |> assert_text(css("#element_result"), expected)
  end

  feature "the resize event payload is empty for a window resize", %{session: session} do
    # The DOM resize event carries no size data of its own (the window's size properties are live
    # globals, not event data), so dispatching records an empty payload - which also proves the
    # window binding fired.
    session
    |> visit(ResizePage)
    |> resize_window(700, 500)
    |> assert_text(css("#window_result"), "%{}")
  end
end
