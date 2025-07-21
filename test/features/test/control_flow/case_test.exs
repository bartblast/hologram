defmodule HologramFeatureTests.ControlFlow.CaseTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.ControlFlow.CasePage

  # single-expression condition / single clause / single-expression clause body
  feature "basic case", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Basic case"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple-expression condition", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Multiple-expression condition"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple clauses", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Multiple clauses"))
    |> assert_text(css("#result"), ":b")
  end

  feature "multiple-expression clause body", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Multiple-expression clause body"))
    |> assert_text(css("#result"), ":b")
  end

  feature "vars matching", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Vars matching"))
    |> assert_text(css("#result"), "{1, 2, 3}")
  end

  feature "vars scoping", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Vars scoping"))
    |> assert_text(css("#result"), "{1, 2, {1, 3}}")
  end

  feature "var match in condition", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Var match in condition"))
    |> assert_text(css("#result"), "{1, 2, {3, 2}}")
  end

  feature "no matching clause", %{session: session} do
    assert_js_error session,
                    "(CaseClauseError) no case clause matching: 3",
                    fn ->
                      session
                      |> visit(CasePage)
                      |> click(button("No matching clause"))
                    end
  end

  feature "error in condition", %{session: session} do
    assert_js_error session,
                    "(RuntimeError) my message",
                    fn ->
                      session
                      |> visit(CasePage)
                      |> click(button("Error in condition"))
                    end
  end

  feature "error_in_clause_body", %{session: session} do
    assert_js_error session,
                    "(ArgumentError) my message",
                    fn ->
                      session
                      |> visit(CasePage)
                      |> click(button("Error in clause body"))
                    end
  end
end
