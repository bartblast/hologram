defmodule HologramFeatureTests.ControlFlow.UnlessTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.ControlFlow.UnlessPage

  # single-expression condition / single-expression unless body / no else expression
  feature "basic case", %{session: session} do
    session
    |> visit(UnlessPage)
    |> click(button("Basic case"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple-expression condition", %{session: session} do
    session
    |> visit(UnlessPage)
    |> click(button("Multiple-expression condition"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple-expression unless body", %{session: session} do
    session
    |> visit(UnlessPage)
    |> click(button("Multiple-expression unless body"))
    |> assert_text(css("#result"), ":a")
  end

  feature "unmet condition, no else body", %{session: session} do
    session
    |> visit(UnlessPage)
    |> click(button("Unmet condition, no else body"))
    |> assert_text(css("#result"), "nil")
  end

  feature "single-expression else body", %{session: session} do
    session
    |> visit(UnlessPage)
    |> click(button("Single-expression else body"))
    |> assert_text(css("#result"), ":b")
  end

  feature "multiple-expression else body", %{session: session} do
    session
    |> visit(UnlessPage)
    |> click(button("Multiple-expression else body"))
    |> assert_text(css("#result"), ":c")
  end

  feature "vars scoping in unless body", %{session: session} do
    session
    |> visit(UnlessPage)
    |> click(button("Vars scoping in unless body"))
    |> assert_text(css("#result"), "{1, 2, 3, {11, 2, 3}}")
  end

  feature "vars scoping in else body", %{session: session} do
    session
    |> visit(UnlessPage)
    |> click(button("Vars scoping in else body"))
    |> assert_text(css("#result"), "{1, 2, 3, {11, 2, 3}}")
  end

  feature "error in condition", %{session: session} do
    assert_js_error session,
                    "(RuntimeError) my message",
                    fn ->
                      session
                      |> visit(UnlessPage)
                      |> click(button("Error in condition"))
                    end
  end

  feature "error in unless body", %{session: session} do
    assert_js_error session,
                    "(ArgumentError) my message",
                    fn ->
                      session
                      |> visit(UnlessPage)
                      |> click(button("Error in unless body"))
                    end
  end

  feature "error in else body", %{session: session} do
    assert_js_error session,
                    "(ArgumentError) my message",
                    fn ->
                      session
                      |> visit(UnlessPage)
                      |> click(button("Error in else body"))
                    end
  end
end
