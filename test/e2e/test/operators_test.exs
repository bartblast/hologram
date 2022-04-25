defmodule HologramE2E.OperatorsTest do
  use HologramE2E.TestCase, async: false

  feature "addition", %{session: session} do
    session
    |> visit("/e2e/operators/addition")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 3"))
  end

  feature "cons", %{session: session} do
    session
    |> visit("/e2e/operators/cons")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = [1, 2, 3]"))
  end

  feature "division", %{session: session} do
    session
    |> visit("/e2e/operators/division")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 2"))
  end

  feature "equal to", %{session: session} do
    session
    |> visit("/e2e/operators/equal-to")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "less than", %{session: session} do
    session
    |> visit("/e2e/operators/less-than")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "list concatenation", %{session: session} do
    session
    |> visit("/e2e/operators/list-concatenation")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = [1, 2, 3, 4]"))
  end

  feature "list subtraction", %{session: session} do
    session
    |> visit("/e2e/operators/list-subtraction")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = [2, 1, 2, 1]"))
  end

  feature "membership", %{session: session} do
    session
    |> visit("/e2e/operators/membership")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "module attribute", %{session: session} do
    session
    |> visit("/e2e/operators/module-attribute")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = test_value"))
  end

  feature "multiplication", %{session: session} do
    session
    |> visit("/e2e/operators/multiplication")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 6"))
  end

  feature "not equal to", %{session: session} do
    session
    |> visit("/e2e/operators/not-equal-to")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "relaxed boolean and", %{session: session} do
    session
    |> visit("/e2e/operators/relaxed-boolean-and")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "relaxed boolean not", %{session: session} do
    session
    |> visit("/e2e/operators/relaxed-boolean-not")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = true"))
  end

  feature "relaxed boolean or", %{session: session} do
    session
    |> visit("/e2e/operators/relaxed-boolean-or")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 2"))
  end

  feature "subtraction", %{session: session} do
    session
    |> visit("/e2e/operators/subtraction")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 4"))
  end

  feature "unary negative", %{session: session} do
    session
    |> visit("/e2e/operators/unary-negative")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = -123"))
  end

  feature "unary positive", %{session: session} do
    session
    |> visit("/e2e/operators/unary-positive")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 123"))
  end
end
