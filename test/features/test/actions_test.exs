defmodule HologramFeatureTests.ActionsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.ActionsPage

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

  # Covered in preceding (syntax) tests:
  # feature "page action triggered from page"

  feature "page action triggered from layout", %{session: session} do
    session
    |> visit(ActionsPage)
    |> click(css("button[id='page_action_6']"))
    |> assert_text(
      css("#page_result"),
      ~r/\{"page_action_6", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
    )
  end

  feature "page action triggered from component", %{session: session} do
    session
    |> visit(ActionsPage)
    |> click(css("button[id='page_action_7']"))
    |> assert_text(
      css("#page_result"),
      ~r/\{"page_action_7", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
    )
  end

  feature "layout action triggered from layout", %{session: session} do
    session
    |> visit(ActionsPage)
    |> click(css("button[id='layout_action_1']"))
    |> assert_text(
      css("#layout_result"),
      ~r/\{"layout_action_1", %\{event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
    )
  end

  feature "layout action triggered from page", %{session: session} do
    session
    |> visit(ActionsPage)
    |> click(css("button[id='layout_action_2']"))
    |> assert_text(
      css("#layout_result"),
      ~r/\{"layout_action_2", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
    )
  end

  feature "component action triggered from component", %{session: session} do
    session
    |> visit(ActionsPage)
    |> click(css("button[id='component_1_action_1']"))
    |> assert_text(
      css("#component_1_result"),
      ~r/\{"component_1_action_1", %\{event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
    )
  end

  feature "component action triggered from page", %{session: session} do
    session
    |> visit(ActionsPage)
    |> click(css("button[id='component_1_action_2']"))
    |> assert_text(
      css("#component_1_result"),
      ~r/\{"component_1_action_2", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
    )
  end

  feature "component action triggered from layout", %{session: session} do
    session
    |> visit(ActionsPage)
    |> click(css("button[id='component_1_action_3']"))
    |> assert_text(
      css("#component_1_result"),
      ~r/\{"component_1_action_3", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
    )
  end
end
