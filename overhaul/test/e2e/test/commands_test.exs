defmodule HologramE2E.CommandsTest do
  use HologramE2E.TestCase, async: false
  alias HologramE2E.Page4

  describe "command spec" do
    feature "command spec without target and params specified as text", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-1"))
      |> assert_has(css("#text-page-4", text: "text updated by action_1_b, state.value = p4"))
    end

    feature "command spec without target and params specified as 1-element tuple", %{
      session: session
    } do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-2"))
      |> assert_has(css("#text-page-4", text: "text updated by action_2_b, state.value = p4"))
    end

    feature "command spec with params", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-3"))
      |> assert_has(
        css("#text-page-4",
          text: "text updated by action_3_b, params.a = 50, params.b = 60, state.value = p4"
        )
      )
    end

    feature "command spec with target ID", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-4"))
      |> assert_has(
        css("#text-component-4", text: "text updated by component_4_action_1_b, state.value = c4")
      )
    end

    feature "command spec with targetID and params", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-5"))
      |> assert_has(
        css("#text-component-4",
          text:
            "text updated by component_4_action_2_b, params.a = 50, params.b = 60, state.value = c4"
        )
      )
    end
  end

  describe "command result" do
    feature "command returning action only, not wrapped in tuple", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-6"))
      |> assert_has(css("#text-page-4", text: "text updated by action_4_b, state.value = p4"))
    end

    feature "command returning action only, wrapped in tuple", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-7"))
      |> assert_has(css("#text-page-4", text: "text updated by action_5_b, state.value = p4"))
    end

    feature "command returning action and params", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-8"))
      |> assert_has(
        css("#text-page-4",
          text: "text updated by action_6_b, params.a = 50, params.b = 60, state.value = p4"
        )
      )
    end

    feature "command returning target ID and action", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-9"))
      |> assert_has(
        css("#text-component-4", text: "text updated by component_4_action_3_b, state.value = c4")
      )
    end

    feature "command returning target ID, action and params", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-10"))
      |> assert_has(
        css("#text-component-4",
          text:
            "text updated by component_4_action_4_b, params.a = 50, params.b = 60, state.value = c4"
        )
      )
    end
  end

  describe "target" do
    feature "default target", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-11"))
      |> assert_has(css("#text-page-4", text: "text updated by action_9_b, state.value = p4"))
    end

    feature "component target", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-12"))
      |> assert_has(
        css("#text-component-4", text: "text updated by component_4_action_5_b, state.value = c4")
      )
    end

    feature "page target", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#component-4-button-1"))
      |> assert_has(css("#text-page-4", text: "text updated by action_10_b, state.value = p4"))
    end

    feature "layout target", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-13"))
      |> assert_has(
        css("#text-default-layout",
          text: "text updated by default_layout_action_2_b, state.value = dl"
        )
      )
    end
  end

  describe "command trigger" do
    feature "command triggered by event", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-14"))
      |> assert_has(css("#text-page-4", text: "text updated by action_11_b, state.value = p4"))
    end

    feature "command trigerred by action", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("#page-4-button-15"))
      |> assert_has(css("#text-page-4", text: "text updated by action_12_b, state.value = p4"))
    end
  end
end
