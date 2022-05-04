defmodule HologramE2E.Runtime.HydrationTest do
  use HologramE2E.TestCase, async: false

  @page_path "/e2e/runtime/hydration"

  feature "page state hydration", %{session: session} do
    session
    |> visit(@page_path)
    |> assert_has(css("#text", text: "count = 100"))
    |> click(css("#button"))
    |> assert_has(css("#text", text: "count = 101"))
  end
end
