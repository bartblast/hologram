defmodule Hologram.Features.RuntimeTest do
  use Hologram.E2ECase, async: true

  @moduletag :e2e

  feature "action without params trigerred by event", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-1-action-1-button"))
    |> assert_has(css("#text", text: "text updated by action_1"))
  end

  feature "action with params trigerred by event", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-1-action-2-button"))
    |> assert_has(css("#text", text: "text updated by action_2_5_6"))
  end

  feature "action without params trigerred by command", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-1-command-3-button"))
    |> assert_has(css("#text", text: "text updated by action_3a"))
  end

  feature "action with params trigerred by command", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-1-command-4-button"))
    |> assert_has(css("#text", text: "text updated by action_4a_5_6"))
  end

  feature "command without params trigerred by event", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-1-command-5-button"))
    |> assert_has(css("#text", text: "text updated by action_5a"))
  end

  feature "command with params trigerred by event", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-1-command-6-button"))
    |> assert_has(css("#text", text: "text updated by action_6a_1_2"))
  end

  feature "command without params trigerred by action", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-1-action-7-button"))
    |> assert_has(css("#text", text: "text updated by action_7a"))
  end

  feature "command with params trigerred by action", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#page-1-action-8-button"))
    |> assert_has(css("#text", text: "text updated by action_8a_5_6"))
  end
end
