defmodule HologramE2E.PatternMatchingTest do
  use HologramE2E.TestCase, async: false

  alias HologramE2E.PatternMatching.ConsOperatorPage
  alias HologramE2E.PatternMatching.ListPage
  alias HologramE2E.PatternMatching.MapPage
  alias HologramE2E.PatternMatching.TuplePage

  describe "cons operator" do
    feature "match expression", %{session: session} do
      session
      |> visit(ConsOperatorPage)
      |> click(css("#button_match_expression"))
      |> assert_has(css("#text", text: "Result = 3"))
    end

    feature "function call", %{session: session} do
      session
      |> visit(ConsOperatorPage)
      |> click(css("#button_function_call"))
      |> assert_has(css("#text", text: "Result = 4"))
    end

    feature "case condition", %{session: session} do
      session
      |> visit(ConsOperatorPage)
      |> click(css("#button_case_condition"))
      |> assert_has(css("#text", text: "Result = 5"))
    end
  end

  describe "list" do
    feature "match expression", %{session: session} do
      session
      |> visit(ListPage)
      |> click(css("#button_match_expression"))
      |> assert_has(css("#text", text: "Result = 3"))
    end

    feature "function call", %{session: session} do
      session
      |> visit(ListPage)
      |> click(css("#button_function_call"))
      |> assert_has(css("#text", text: "Result = 5"))
    end

    feature "case condition", %{session: session} do
      session
      |> visit(ListPage)
      |> click(css("#button_case_condition"))
      |> assert_has(css("#text", text: "Result = 7"))
    end
  end

  describe "map" do
    feature "match expression", %{session: session} do
      session
      |> visit(MapPage)
      |> click(css("#button_match_expression"))
      |> assert_has(css("#text", text: "Result = 3"))
    end

    feature "function call", %{session: session} do
      session
      |> visit(MapPage)
      |> click(css("#button_function_call"))
      |> assert_has(css("#text", text: "Result = 5"))
    end

    feature "case condition", %{session: session} do
      session
      |> visit(MapPage)
      |> click(css("#button_case_condition"))
      |> assert_has(css("#text", text: "Result = 7"))
    end
  end

  describe "tuple" do
    feature "match expression", %{session: session} do
      session
      |> visit(TuplePage)
      |> click(css("#button_match_expression"))
      |> assert_has(css("#text", text: "Result = 3"))
    end

    feature "function call", %{session: session} do
      session
      |> visit(TuplePage)
      |> click(css("#button_function_call"))
      |> assert_has(css("#text", text: "Result = 5"))
    end

    feature "case condition", %{session: session} do
      session
      |> visit(TuplePage)
      |> click(css("#button_case_condition"))
      |> assert_has(css("#text", text: "Result = 7"))
    end
  end

  # feature "for expression": tested in test/e2e/test/control_flow_test.exs
end
