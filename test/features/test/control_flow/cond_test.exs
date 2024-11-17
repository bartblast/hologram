defmodule HologramFeatureTests.ControlFlow.CondTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.ControlFlow.CondPage

  # single-expression clause condition / single clause / single-expression clause body
  feature "basic case", %{session: session} do
    session
    |> visit(CondPage)
    |> click(button("Basic case"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple-expression clause condition", %{session: session} do
    session
    |> visit(CondPage)
    |> click(button("Multiple-expression clause condition"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple clauses", %{session: session} do
    session
    |> visit(CondPage)
    |> click(button("Multiple clauses"))
    |> assert_text(css("#result"), ":b")
  end

  feature "multiple-expression clause body", %{session: session} do
    session
    |> visit(CondPage)
    |> click(button("Multiple-expression clause body"))
    |> assert_text(css("#result"), ":b")
  end

  feature "evaluates the first clause with truthy condition", %{session: session} do
    session
    |> visit(CondPage)
    |> click(button("Evaluates the first clause with truthy condition"))
    |> assert_text(css("#result"), ":c")
  end

  feature "vars scoping", %{session: session} do
    session
    |> visit(CondPage)
    |> click(button("Vars scoping"))
    |> assert_text(css("#result"), "{1, 2, 3, {14, 5, 3}}")
  end

  feature "no matching clause", %{session: session} do
    assert_js_error session,
                    "(CondClauseError) no cond clause evaluated to a truthy value",
                    fn ->
                      session
                      |> visit(CondPage)
                      |> click(button("No matching clause"))
                    end
  end

  feature "error in clause condition", %{session: session} do
    assert_js_error session,
                    "(RuntimeError) my message",
                    fn ->
                      session
                      |> visit(CondPage)
                      |> click(button("Error in clause condition"))
                    end
  end

  feature "error in clause body", %{session: session} do
    assert_js_error session,
                    "(ArgumentError) my message",
                    fn ->
                      session
                      |> visit(CondPage)
                      |> click(button("Error in clause body"))
                    end
  end
end
