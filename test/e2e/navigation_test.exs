defmodule Hologram.Features.NavigationTest do
  use Hologram.E2ECase, async: false

  @moduletag :e2e

  feature "link", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-2-link"))
    |> assert_has(css("h1", text: "Page 2"))
    |> click(css("#page-2-update-text-button"))
    |> assert_has(css("#text", text: "updated text"))

    assert current_path(session) == "/e2e/page-2"
  end

  feature "back button", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-2-link"))
    |> click(css("#page-2-back-button"))
    |> assert_has(css("h1", text: "Page 1"))
    |> click(css("#page-1-action-1-button"))
    |> assert_has(css("#text", text: "text updated by action_1"))

    assert current_path(session) == "/e2e/page-1"
  end

  feature "forward button", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-2-link"))
    |> click(css("#page-2-back-button"))
    |> click(css("#page-1-forward-button"))
    |> assert_has(css("h1", text: "Page 2"))
    |> click(css("#page-2-update-text-button"))
    |> assert_has(css("#text", text: "updated text"))

    assert current_path(session) == "/e2e/page-2"
  end
end
