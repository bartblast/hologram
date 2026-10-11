defmodule HologramCowboyTests.CommandTest do
  use HologramCowboyTests.TestCase, async: false

  alias HologramCowboyTests.CommandPage

  feature "a command round-trips", %{session: session} do
    session
    |> visit(CommandPage)
    |> click(css("#run"))
    |> assert_text(css("#result"), "answered with 42")
  end
end
