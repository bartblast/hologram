defmodule Hologram.Features.ActionsTest do
  use Hologram.Test.E2ECase, async: false

  @moduletag :e2e

  describe "spec" do
    feature "action spec without target and params specified as text", %{session: session} do
      session
      |> visit("/e2e/page-1")
      |> click(css("#page-1-button-1"))
      |> assert_has(css("#text-page-1", text: "text updated by action_1, state.value = p1"))
    end

    feature "action spec without target and params specified as 1-element tuple", %{session: session} do
      session
      |> visit("/e2e/page-1")
      |> click(css("#page-1-button-2"))
      |> assert_has(css("#text-page-1", text: "text updated by action_2, state.value = p1"))
    end

    feature "action spec with params", %{session: session} do
      session
      |> visit("/e2e/page-1")
      |> click(css("#page-1-button-3"))
      |> assert_has(css("#text-page-1", text: "text updated by action_3, params.a = 5, params.b = 6, state.value = p1"))
    end

    feature "action spec with target ID", %{session: session} do
      session
      |> visit("/e2e/page-1")
      |> click(css("#page-1-button-4"))
      |> assert_has(css("#text-component-3", text: "text updated by component_3_action_1, state.value = c3"))
    end

    feature "action spec with targetID and params", %{session: session} do
      session
      |> visit("/e2e/page-1")
      |> click(css("#page-1-button-5"))
      |> assert_has(css("#text-component-3", text: "text updated by component_3_action_2, params.a = 5, params.b = 6, state.value = c3"))
    end
  end

  describe "result" do
    # same test as feature "action spec without target and params specified as text"
    # feature "action returning state only, not wrapped in tuple"

    feature "action returning state only, wrapped in tuple", %{session: session} do
      session
      |> visit("/e2e/page-1")
      |> click(css("#page-1-button-6"))
      |> assert_has(css("#text-page-1", text: "text updated by action_4, state.value = p1"))
    end

    feature "action returning state and command", %{session: session} do
      session
      |> visit("/e2e/page-1")
      |> click(css("#page-1-button-7"))
      |> assert_has(css("#text-page-1", text: "text updated by action_5_b triggered by command_1, state.value = p1"))
    end

    feature "action returning state, command and params", %{session: session} do
      session
      |> visit("/e2e/page-1")
      |> click(css("#page-1-button-8"))
      |> assert_has(css("#text-page-1", text: "text updated by action_6_b triggered by command_2, params.a = 10, params.b = 20, state.value = p1"))
    end

    feature "action returning state, target ID and command", %{session: session} do
      # session
      # |> visit("/e2e/page-1")
      # |> click(css("#page-1-button-8"))
      # |> assert_has(css("#text-page-1", text: "text updated by action_6_b triggered by command_2, params.a = 10, params.b = 20, state.value = p1"))
    end

    feature "action returning state, target ID, command and params", %{session: session} do

    end
  end

  describe "target" do
    # same test as feature "action spec without target and params specified as text"
    # feature "default target"

    # same test as feature "action spec with target ID"
    # feature "component target"

    feature "page target" do

    end

    feature "layout target" do

    end
  end
end
