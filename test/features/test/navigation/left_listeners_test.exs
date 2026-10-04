defmodule HologramFeatureTests.Navigation.LeftListenersTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Navigation.LeftListenersDestinationPage
  alias HologramFeatureTests.Navigation.LeftListenersPage

  # The destination's bundle is held back so the stretch between its patch and its mount is wide
  # enough for the browser to deliver what the left page's listeners observe of the patch - here the
  # resize observer reporting its detached element at 0x0. Left attached, that dispatch carries the
  # destination's epoch, is held for the mount, and raises there against a registry that no longer
  # has the box. The destination's result proves the mount ran and released the click's own dispatch.
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
end
