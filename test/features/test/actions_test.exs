defmodule HologramFeatureTests.ActionsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.ActionsPage

  describe "syntax" do
    feature "text syntax", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_1']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_1", %\{event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "expression shorthand syntax without params", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_2']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_2", %\{event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "expression shorthand syntax with params", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_3']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_3", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "expression longhand syntax", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_4']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_4", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "multi-chunk syntax", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_5']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_5", %\{event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end
  end

  describe "layout action" do
    feature "triggered from layout (default target)", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='layout_action_1']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{"layout_action_1", %\{event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='layout_action_2']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{"layout_action_2", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='layout_action_3']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{"layout_action_3", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end
  end

  describe "page action" do
    # Covered in preceding (syntax) tests:
    # feature "triggered from page (default target)"

    feature "triggered from layout", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_6']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_6", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_7']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_7", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end
  end

  describe "component action" do
    feature "triggered from layout", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='component_1_action_3']"))
      |> assert_text(
        css("#component_1_result"),
        ~r/\{"component_1_action_3", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='component_1_action_2']"))
      |> assert_text(
        css("#component_1_result"),
        ~r/\{"component_1_action_2", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from component (default target)", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='component_1_action_1']"))
      |> assert_text(
        css("#component_1_result"),
        ~r/\{"component_1_action_1", %\{event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end
  end

  describe "component struct mutations" do
    feature "emitted context", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_8']"))
      |> assert_text(css("#component_1_prop_1"), ":updated_value")
    end

    feature "next action", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_9']"))
      |> assert_text(css("#page_result"), ~s/{"page_action_10", %{x: 10, y: 20}}/)
    end

    feature "next command", %{session: session} do
      session
      |> visit(ActionsPage)
      |> click(css("button[id='page_action_11']"))
      |> assert_text(css("#page_result"), ~s/{"page_action_12", %{x: 10, y: 20}}/)
    end

    # Covered in navigation test suite
    # feature "next page"

    # Covered in preceding (syntax) tests:
    # feature "state"
  end
end
