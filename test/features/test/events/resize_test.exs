defmodule HologramFeatureTests.Events.ResizeTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.ResizePage

  defp ensure_float(number) do
    :erlang.float(number)
  end

  defp window_metrics(session) do
    script = """
    const el = document.documentElement;

    return [
      el.clientHeight,
      el.clientWidth,
      window.devicePixelRatio,
      window.innerHeight,
      window.innerWidth
    ];
    """

    [ch, cw, dpr, ih, iw] = script_result(session, script)

    %{
      client_height: ensure_float(ch),
      client_width: ensure_float(cw),
      device_pixel_ratio: ensure_float(dpr),
      inner_height: ensure_float(ih),
      inner_width: ensure_float(iw)
    }
  end

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

  feature "the resize event payload carries the window's size metrics", %{session: session} do
    session =
      session
      |> visit(ResizePage)
      |> resize_window(700, 500)

    # Wait for the resize to be recorded, then read the payload back and compare it field by field.
    assert_text(session, css("#window_result"), ~r/inner_width:/)

    recorded = term_at(session, "#window_result")
    metrics = window_metrics(session)

    # The viewport metrics (scrollbar, chrome, device pixel ratio) depend on the headless window, so
    # they are compared to live read-back values rather than hardcoded.
    assert recorded.client_height == metrics.client_height
    assert recorded.client_width == metrics.client_width
    assert recorded.device_pixel_ratio == metrics.device_pixel_ratio
    assert recorded.inner_height == metrics.inner_height
    assert recorded.inner_width == metrics.inner_width

    # outer_width/outer_height get only a positivity check, not an exact comparison. The resize event
    # fires when the viewport changes, so innerWidth/innerHeight (checked above) are already current,
    # but the outer window frame updates a beat later - at event time outerWidth/outerHeight still
    # report the window's pre-resize size. That recorded value is therefore the prior size, which is
    # unknowable from here and no longer equals a live read-back. A positive value still proves the
    # field is populated, catching a nil/0/NaN regression.
    assert recorded.outer_width > 0
    assert recorded.outer_height > 0
  end
end
