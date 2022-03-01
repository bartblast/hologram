defmodule HologramE2E.NavigationTest do
  use HologramE2E.TestCase, async: false

  @moduletag :e2e

  feature "anchor", %{session: session} do
    session
    |> visit("/e2e/page-5")
    |> click(css("#page-2-link"))
    |> assert_has(css("h1", text: "Page 2"))
    |> click(css("#page-2-update-text-button"))
    |> assert_has(css("#page-2-text", text: "text updated by page 2 update button"))

    assert current_path(session) == "/e2e/page-2"
  end

  feature "back button", %{session: session} do
    session
    |> visit("/e2e/page-5")
    |> click(css("#page-2-link"))
    |> click(css("#page-2-back-button"))
    |> assert_has(css("h1", text: "Page 5"))
    |> click(css("#page-5-update-text-button"))
    |> assert_has(css("#page-5-text", text: "text updated by page 5 update button"))

    assert current_path(session) == "/e2e/page-5"
  end

  feature "forward button", %{session: session} do
    session
    |> visit("/e2e/page-5")
    |> click(css("#page-2-link"))
    |> click(css("#page-2-back-button"))
    |> click(css("#page-5-forward-button"))
    |> assert_has(css("h1", text: "Page 2"))
    |> click(css("#page-2-update-text-button"))
    |> assert_has(css("#page-2-text", text: "text updated by page 2 update button"))

    assert current_path(session) == "/e2e/page-2"
  end
end
