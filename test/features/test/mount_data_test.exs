defmodule HologramFeatureTests.MountDataTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.MountDataPage

  # The page's state carries a closing script tag. The server writes that state into the inline
  # script the client reads its mount data from, so an unescaped "<" ends the script element
  # early: the mount data is never defined, the page never mounts, and the rest of the state
  # renders as page text.
  feature "page state holding a closing script tag", %{session: session} do
    session
    |> visit(MountDataPage)
    |> assert_text(css("#snippet"), "<div><script>alert(1)</script></div>")
    |> click(css("#button"))
    |> assert_text(css("#status"), "clicked")
  end
end
