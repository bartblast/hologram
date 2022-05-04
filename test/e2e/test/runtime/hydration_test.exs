defmodule HologramE2E.Runtime.HydrationTest do
  use HologramE2E.TestCase, async: false

  @page_path "/e2e/runtime/hydration"

  feature "page state hydration", %{session: session} do
    session
    |> visit(@page_path)
    |> assert_has(css("#page-text", text: "page count = 100"))
    |> click(css("#page-button"))
    |> assert_has(css("#page-text", text: "page count = 101"))
  end

  feature "layout state hydration", %{session: session} do
    session
    |> visit(@page_path)
    |> assert_has(css("#layout-text", text: "layout count = 200"))
    |> click(css("#layout-button"))
    |> assert_has(css("#layout-text", text: "layout count = 201"))
  end
end
