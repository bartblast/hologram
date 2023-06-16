defmodule HologramE2E.ControlFlowTest do
  use HologramE2E.TestCase, async: false

  alias HologramE2E.ControlFlow.AnonymousFunctionCallPage
  alias HologramE2E.ControlFlow.CaseExpressionPage
  alias HologramE2E.ControlFlow.ForExpressionPage

  describe "anonymous function call" do
    feature "regular syntax", %{session: session} do
      session
      |> visit(AnonymousFunctionCallPage)
      |> click(css("#button_regular_syntax"))
      |> assert_has(css("#text", text: "Result = 6"))
    end

    # TODO: implement
    # feature "shorthand syntax"
  end

  feature "case", %{session: session} do
    session
    |> visit(CaseExpressionPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 22"))
  end

  describe "for expression" do
    test "single generator", %{session: session} do
      session
      |> visit(ForExpressionPage)
      |> click(css("#button_single_generator"))
      |> assert_has(css("#text", text: "Result = [1, 4, 9]"))
    end

    test "multiple generators", %{session: session} do
      session
      |> visit(ForExpressionPage)
      |> click(css("#button_multiple_generators"))
      |> assert_has(css("#text", text: "Result = [3, 4, 6, 8]"))
    end

    test "nested", %{session: session} do
      session
      |> visit(ForExpressionPage)
      |> click(css("#button_nested"))
      |> assert_has(css("#text", text: "Result = [[1, 9, 16], [2, 9, 16]]"))
    end

    test "pattern matching", %{session: session} do
      session
      |> visit(ForExpressionPage)
      |> click(css("#button_pattern_matching"))
      |> assert_has(css("#text", text: "Result = [2, 12]"))
    end
  end
end
