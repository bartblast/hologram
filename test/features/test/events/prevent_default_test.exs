defmodule HologramFeatureTests.Events.PreventDefaultTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.PreventDefaultPage

  feature "prevent_default blocks the native default while a plain binding allows it",
          %{session: session} do
    session
    |> visit(PreventDefaultPage)
    |> send_keys(css("#prevented_input"), [:enter])
    |> assert_text(css("#result"), "{true, false, false, false}")
    |> send_keys(css("#plain_input"), [:enter])
    |> assert_text(css("#result"), "{true, false, true, true}")
  end
end
