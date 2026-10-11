defmodule HologramFeatureTests.Navigation.LeftListenersTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Navigation.LeftListenersDestinationPage
  alias HologramFeatureTests.Navigation.LeftListenersPage

  # Every feature here holds the destination's bundle back, so the stretch between its patch and
  # its mount is wide enough for the browser to deliver what the left page's listeners observe in
  # it. Left attached, such a dispatch carries the destination's epoch, is held for the mount, and
  # raises there against a registry that no longer has the box. The destination's result proves
  # the mount ran and released the click's own dispatch.

  # The link sits outside the panel, so the click on it is an outside click the page being left
  # handles as its own, before it navigates. The click on the destination's title is the one in
  # question: the binding is a document-level listener, so it is still the left page's until the
  # mount, and a click on the markup patched in reaches it.
  feature "a click_outside binding of the page being left does not dispatch into the destination",
          %{session: session} do
    session
    |> simulate_slow_page_bundle(4_000)
    |> visit(LeftListenersPage, kind: "click_outside")
    |> click(link("Destination link"))
    |> click(css("#destination_title"))
    |> assert_page(LeftListenersDestinationPage, kind: "click_outside")
    |> click(button("Put destination result"))
    |> assert_text(css("#destination_result"), ~s/"click_outside"/)
  end

  # The container is 900px short of its bottom edge at the mount, so it does not fire there. Once
  # detached, every one of its scroll metrics reads 0, which puts the edge at a distance of 0 -
  # within range - and the observer watching it reports the change.
  feature "a reach observer of the page being left does not dispatch into the destination",
          %{session: session} do
    session
    |> simulate_slow_page_bundle(4_000)
    |> visit(LeftListenersPage, kind: "reach")
    |> click(link("Destination link"))
    |> assert_page(LeftListenersDestinationPage, kind: "reach")
    |> click(button("Put destination result"))
    |> assert_text(css("#destination_result"), ~s/"reach"/)
  end

  # The observer reports its detached element at 0x0.
  feature "a resize observer of the page being left does not dispatch into the destination",
          %{session: session} do
    session
    |> simulate_slow_page_bundle(4_000)
    |> visit(LeftListenersPage, kind: "resize")
    |> click(link("Destination link"))
    |> assert_page(LeftListenersDestinationPage, kind: "resize")
    |> click(button("Put destination result"))
    |> assert_text(css("#destination_result"), ~s/"resize"/)
  end

  # A window listener observes nothing of the patch by itself, so the event is driven: the title
  # appearing says the destination is patched in, the held-back bundle says it is not mounted, and
  # the resize lands between the two. A key press, or the scroll a shorter destination causes by
  # clamping the offset, would reach the same listener.
  feature "a window binding of the page being left does not dispatch into the destination",
          %{session: session} do
    session
    |> simulate_slow_page_bundle(4_000)
    |> visit(LeftListenersPage, kind: "window_resize")
    |> click(link("Destination link"))
    |> assert_has(css("#destination_title"))
    |> resize_window(700, 500)
    |> assert_page(LeftListenersDestinationPage, kind: "window_resize")
    |> click(button("Put destination result"))
    |> assert_text(css("#destination_result"), ~s/"window_resize"/)
  end
end
