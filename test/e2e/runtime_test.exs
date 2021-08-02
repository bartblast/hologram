defmodule Hologram.Features.RuntimeTest do
  use Hologram.E2ECase, async: true

  @moduletag :e2e

  feature "action without params trigerred by event", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button_1"))
    |> assert_has(css("#text", text: "text updated by action_1"))
  end

  feature "action with params trigerred by event", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button_2"))
    |> assert_has(css("#text", text: "text updated by action_2_5_6"))
  end

  feature "action without params trigerred by command", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button_3"))
    |> assert_has(css("#text", text: "text updated by action_3a"))
  end

  feature "action with params trigerred by command", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button_4"))
    |> assert_has(css("#text", text: "text updated by action_4a_5_6"))
  end

  feature "command without params trigerred by event", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button_5"))
    |> assert_has(css("#text", text: "text updated by action_5a"))
  end

  feature "command with params trigerred by event", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button_6"))
    |> assert_has(css("#text", text: "text updated by action_6a_1_2"))
  end

  feature "command without params trigerred by action", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button_7"))
    |> assert_has(css("#text", text: "text updated by action_7a"))
  end

  feature "command with params trigerred by action", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button_8"))
    |> assert_has(css("#text", text: "text updated by action_8a_5_6"))
  end
end
