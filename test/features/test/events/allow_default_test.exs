defmodule HologramFeatureTests.Events.AllowDefaultTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.AllowDefault.Page1
  alias HologramFeatureTests.Events.AllowDefault.Page2

  feature "allow_default lets the native form submission proceed while a plain binding prevents it",
          %{session: session} do
    session
    |> visit(Page1)
    |> click(css("#prevented_submit"))
    |> assert_text(css("#result"), "{false, true}")
    |> click(css("#allowed_submit"))
    |> assert_page(Page2)
  end
end
