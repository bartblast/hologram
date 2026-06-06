defmodule HologramFeatureTests.Events.ClickOutsideTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.ClickOutsidePage

  feature "opening the element does not immediately close it", %{session: session} do
    session
    |> visit(ClickOutsidePage)
    |> click(css("#open"))
    |> assert_has(css("#panel"))
    # The opening click must not register as an outside click - the document listener is installed
    # only on the open re-render, a turn after the click. The inside click is a happens-after
    # barrier: the opening click is queued before it, so once the note lands the opening click has
    # been processed and a zero close count is reliable.
    |> click(css("#inside"))
    |> assert_text(css("#note_result"), "1")
    |> assert_text(css("#close_result"), "0")
    |> assert_has(css("#panel"))
  end

  feature "a click inside the element keeps it open", %{session: session} do
    session
    |> visit(ClickOutsidePage)
    |> click(css("#open"))
    |> assert_has(css("#panel"))
    # Two inside clicks. An inside click's own close would be queued during that same click, so the
    # second click's note is the happens-after barrier: once the note count reaches 2, the first
    # inside click has been fully processed and a zero close count proves it did not close.
    |> click(css("#inside"))
    |> click(css("#inside"))
    |> assert_text(css("#note_result"), "2")
    |> assert_text(css("#close_result"), "0")
    |> assert_has(css("#panel"))
  end

  feature "a click outside the element closes it", %{session: session} do
    session
    |> visit(ClickOutsidePage)
    |> click(css("#open"))
    |> assert_has(css("#panel"))
    |> click(css("#outside"))
    |> assert_text(css("#close_result"), "1")
    |> refute_has(css("#panel"))
  end
end
