defmodule HologramCowboyTests.PageTest do
  use HologramCowboyTests.TestCase, async: false

  alias HologramCowboyTests.PlainPage

  feature "a page request is served", %{session: session} do
    session
    |> visit(PlainPage)
    |> assert_text(css("#text"), "Served through Cowboy")
  end
end
