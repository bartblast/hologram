defmodule HologramFeatureTests.ActionsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Actions.Page1
  alias HologramFeatureTests.Actions.Page2
  alias HologramFeatureTests.Actions.Page3
  alias HologramFeatureTests.Actions.Page4
  alias HologramFeatureTests.Actions.Page5
  alias HologramFeatureTests.Actions.Page6

  describe "syntax" do
    feature "text syntax", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_1']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_1", %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "expression shorthand syntax without params", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_2']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_2", %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "expression shorthand syntax with params", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_3']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_3", %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "expression longhand syntax", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_4']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_4", %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "multi-chunk syntax", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_5']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_5", %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "layout action" do
    feature "triggered from layout (default target)", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='layout_action_1']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{"layout_action_1", %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='layout_action_2']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{"layout_action_2", %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='layout_action_3']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{"layout_action_3", %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "page action" do
    # Covered in preceding (syntax) tests:
    # feature "triggered from page (default target)"

    feature "triggered from layout", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_6']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_6", %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_7']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_action_7", %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "component action" do
    feature "triggered from layout", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='component_1_action_3']"))
      |> assert_text(
        css("#component_1_result"),
        ~r/\{"component_1_action_3", %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='component_1_action_2']"))
      |> assert_text(
        css("#component_1_result"),
        ~r/\{"component_1_action_2", %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from component (default target)", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='component_1_action_1']"))
      |> assert_text(
        css("#component_1_result"),
        ~r/\{"component_1_action_1", %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "component struct mutations" do
    feature "emitted context", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_8']"))
      |> assert_text(css("#component_1_prop_1"), ":updated_value")
    end

    feature "next action", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_9']"))
      |> assert_text(css("#page_result"), ~s/{"page_action_10", %{x: 10, y: 20}}/)
    end

    feature "next command", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_11']"))
      |> assert_text(css("#page_result"), ~s/{"page_action_12", %{x: 10, y: 20}}/)
    end

    # Covered in navigation test suite
    # feature "next page"

    # Covered in preceding (syntax) tests:
    # feature "state"
  end

  describe "actions queued in server-side init/3" do
    feature "page init/3, target not specified", %{session: session} do
      session
      |> visit(Page2)
      |> assert_text(css("#page_result"), ~s'{:page_action_result, %{queued_from: "page"}}')
    end

    feature "page init/3, target is specified", %{session: session} do
      session
      |> visit(Page3)
      |> assert_text(
        css("#component_1_result"),
        ~s'{:component_1_action_result, %{queued_from: "page"}}'
      )
    end

    feature "component init/3, target not specified", %{session: session} do
      session
      |> visit(Page4)
      |> assert_text(
        css("#component_2_result"),
        ~s'{:component_2_action_result, %{queued_from: "component_2"}}'
      )
    end

    feature "component init/3, target is specified", %{session: session} do
      session
      |> visit(Page5)
      |> assert_text(
        css("#component_4_result"),
        ~s'{:component_4_action_result, %{queued_from: "component_3"}}'
      )
    end

    # The order is based on CIDs in ascending alphabetical order (page's CID is "page", layout's CID is "layout")
    feature "all actions queued in server-side inits are executed in deterministic order", %{
      session: session
    } do
      session
      |> visit(Page6)
      |> assert_text(
        css("#combined_result"),
        "[:component_5_action_executed, :component_9_action_executed, :layout_action_executed, :component_7_action_executed, :page_action_executed, :component_6_action_executed]"
      )
    end
  end
end
