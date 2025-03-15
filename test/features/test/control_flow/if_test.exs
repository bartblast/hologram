defmodule HologramFeatureTests.ControlFlow.IfTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.ControlFlow.IfPage

  # single-expression condition / single-expression if body / no else expression
  feature "basic case", %{session: session} do
    session
    |> visit(IfPage)
    |> click(button("Basic case"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple-expression condition", %{session: session} do
    session
    |> visit(IfPage)
    |> click(button("Multiple-expression condition"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple-expression if body", %{session: session} do
    session
    |> visit(IfPage)
    |> click(button("Multiple-expression if body"))
    |> assert_text(css("#result"), ":a")
  end

  feature "unmet condition, no else body", %{session: session} do
    session
    |> visit(IfPage)
    |> click(button("Unmet condition, no else body"))
    |> assert_text(css("#result"), "nil")
  end

  feature "single-expression else body", %{session: session} do
    session
    |> visit(IfPage)
    |> click(button("Single-expression else body"))
    |> assert_text(css("#result"), ":b")
  end

  feature "multiple-expression else body", %{session: session} do
    session
    |> visit(IfPage)
    |> click(button("Multiple-expression else body"))
    |> assert_text(css("#result"), ":c")
  end

  feature "versioned x var handling", %{session: session} do
    session
    |> visit(IfPage)
    |> click(button("Versioned x var handling"))
    |> assert_text(css("#result"), "11")
  end

  feature "vars scoping in if body", %{session: session} do
    session
    |> visit(IfPage)
    |> click(button("Vars scoping in if body"))
    |> assert_text(css("#result"), "{1, 2, 3, {11, 2, 3}}")
  end

  feature "vars scoping in else body", %{session: session} do
    session
    |> visit(IfPage)
    |> click(button("Vars scoping in else body"))
    |> assert_text(css("#result"), "{1, 2, 3, {11, 2, 3}}")
  end

  feature "error in condition", %{session: session} do
    assert_js_error session,
                    "(RuntimeError) my message",
                    fn ->
                      session
                      |> visit(IfPage)
                      |> click(button("Error in condition"))
                    end
  end

  feature "error in if body", %{session: session} do
    assert_js_error session,
                    "(ArgumentError) my message",
                    fn ->
                      session
                      |> visit(IfPage)
                      |> click(button("Error in if body"))
                    end
  end

  feature "error in else body", %{session: session} do
    assert_js_error session,
                    "(ArgumentError) my message",
                    fn ->
                      session
                      |> visit(IfPage)
                      |> click(button("Error in else body"))
                    end
  end
end
