defmodule HologramFeatureTests.Events.AllowDefaultTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.AllowDefaultPage

  feature "allow_default lets the native default proceed while a plain binding prevents it",
          %{session: session} do
    session
    |> visit(AllowDefaultPage)
    |> click(css("#allowed_checkbox"))
    |> assert_text(css("#result"), "{true, false}")
    |> assert_has(css("#allowed_checkbox:checked"))
    |> click(css("#blocked_checkbox"))
    |> assert_text(css("#result"), "{true, true}")
    |> refute_has(css("#blocked_checkbox:checked"))
  end
end
