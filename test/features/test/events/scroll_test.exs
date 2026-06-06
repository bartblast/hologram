defmodule HologramFeatureTests.Events.ScrollTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.ScrollPage

  feature "scrolling an element dispatches with its scroll position", %{session: session} do
    session
    |> visit(ScrollPage)
    |> execute_script(
      "const el = document.getElementById('scroller'); el.scrollLeft = 120; el.scrollTop = 250;"
    )
    |> assert_text(css("#element_result"), "{120.0, 250.0}")
  end

  feature "scrolling the page dispatches to a window binding", %{session: session} do
    session
    |> visit(ScrollPage)
    |> execute_script("window.scrollTo(180, 300);")
    |> assert_text(css("#window_result"), "{180.0, 300.0}")
  end

  feature "scrolling the page dispatches to a document binding", %{session: session} do
    session
    |> visit(ScrollPage)
    |> execute_script("window.scrollTo(140, 220);")
    |> assert_text(css("#document_result"), "{140.0, 220.0}")
  end
end
