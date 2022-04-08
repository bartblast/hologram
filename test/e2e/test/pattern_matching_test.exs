defmodule HologramE2E.PatternMatchingTest do
  use HologramE2E.TestCase, async: false

  @moduletag :e2e

  describe "map" do
    feature "match expression", %{session: session} do
      session
      |> visit("/e2e/pattern-matching/map")
      |> click(css("#button_match_expression"))
      |> assert_has(css("#text", text: "Result = 3"))
    end

    feature "function call", %{session: session} do
      session
      |> visit("/e2e/pattern-matching/map")
      |> click(css("#button_function_call"))
      |> assert_has(css("#text", text: "Result = 5"))
    end

    feature "case condition", %{session: session} do
      session
      |> visit("/e2e/pattern-matching/map")
      |> click(css("#button_case_condition"))
      |> assert_has(css("#text", text: "Result = 7"))
    end
  end

  describe "tuple" do
    feature "match expression", %{session: session} do
      session
      |> visit("/e2e/pattern-matching/tuple")
      |> click(css("#button_match_expression"))
      |> assert_has(css("#text", text: "Result = 3"))
    end

    feature "function call", %{session: session} do
      session
      |> visit("/e2e/pattern-matching/tuple")
      |> click(css("#button_function_call"))
      |> assert_has(css("#text", text: "Result = 5"))
    end

    feature "case condition", %{session: session} do
      session
      |> visit("/e2e/pattern-matching/tuple")
      |> click(css("#button_case_condition"))
      |> assert_has(css("#text", text: "Result = 7"))
    end
  end
end
