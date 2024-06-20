defmodule HologramE2E.Runtime.ActionsTest do
  use HologramE2E.TestCase, async: false
  alias HologramE2E.Runtime.ActionsPage

  describe "action result" do
    feature "action returning state only, not wrapped in tuple", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("#button-11"))
      |> assert_has(css("#text", text: "text updated by action_9, state.value = p1"))
    end

    feature "action returning state only, wrapped in tuple", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("#button-6"))
      |> assert_has(css("#text", text: "text updated by action_4, state.value = p1"))
    end

    feature "action returning state and command", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("#button-7"))
      |> assert_has(
        css("#text",
          text: "text updated by action_5_b triggered by command_1, state.value = p1"
        )
      )
    end

    feature "action returning state, command and params", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("#button-8"))
      |> assert_has(
        css("#text",
          text:
            "text updated by action_6_b triggered by command_2, params.a = 10, params.b = 20, state.value = p1"
        )
      )
    end

    feature "action returning state, target ID and command", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("#button-9"))
      |> assert_has(
        css("#text",
          text: "text updated by action_7_b triggered by component_3_command_1, state.value = p1"
        )
      )
    end

    feature "action returning state, target ID, command and params", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("#button-10"))
      |> assert_has(
        css("#text",
          text:
            "text updated by action_8_b triggered by component_3_command_2, params.a = 10, params.b = 20, state.value = p1"
        )
      )
    end
  end
end
