defmodule HologramE2E.OperatorsTest do
  use HologramE2E.TestCase, async: false

  alias HologramE2E.Operators.AdditionPage
  alias HologramE2E.Operators.ConsPage
  alias HologramE2E.Operators.DivisionPage
  alias HologramE2E.Operators.EqualToPage
  alias HologramE2E.Operators.LessThanPage
  alias HologramE2E.Operators.ListConcatenationPage
  alias HologramE2E.Operators.ListSubtractionPage
  alias HologramE2E.Operators.MembershipPage
  alias HologramE2E.Operators.ModuleAttributePage
  alias HologramE2E.Operators.MultiplicationPage
  alias HologramE2E.Operators.NotEqualToPage
  alias HologramE2E.Operators.RelaxedBooleanAndPage
  alias HologramE2E.Operators.RelaxedBooleanNotPage
  alias HologramE2E.Operators.RelaxedBooleanOrPage
  alias HologramE2E.Operators.SubtractionPage
  alias HologramE2E.Operators.UnaryNegativePage
  alias HologramE2E.Operators.UnaryPositivePage

  feature "addition", %{session: session} do
    session
    |> visit(AdditionPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 3"))
  end

  feature "cons", %{session: session} do
    session
    |> visit(ConsPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = [1, 2, 3]"))
  end

  feature "division", %{session: session} do
    session
    |> visit(DivisionPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 2"))
  end

  feature "equal to", %{session: session} do
    session
    |> visit(EqualToPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "less than", %{session: session} do
    session
    |> visit(LessThanPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "list concatenation", %{session: session} do
    session
    |> visit(ListConcatenationPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = [1, 2, 3, 4]"))
  end

  feature "list subtraction", %{session: session} do
    session
    |> visit(ListSubtractionPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = [2, 1, 2, 1]"))
  end

  feature "membership", %{session: session} do
    session
    |> visit(MembershipPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "module attribute", %{session: session} do
    session
    |> visit(ModuleAttributePage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = test_value"))
  end

  feature "multiplication", %{session: session} do
    session
    |> visit(MultiplicationPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 6"))
  end

  feature "not equal to", %{session: session} do
    session
    |> visit(NotEqualToPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "relaxed boolean and", %{session: session} do
    session
    |> visit(RelaxedBooleanAndPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "relaxed boolean not", %{session: session} do
    session
    |> visit(RelaxedBooleanNotPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "relaxed boolean or", %{session: session} do
    session
    |> visit(RelaxedBooleanOrPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 2"))
  end

  feature "subtraction", %{session: session} do
    session
    |> visit(SubtractionPage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 4"))
  end

  feature "unary negative", %{session: session} do
    session
    |> visit(UnaryNegativePage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = -123"))
  end

  feature "unary positive", %{session: session} do
    session
    |> visit(UnaryPositivePage)
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 123"))
  end
end
