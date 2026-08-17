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
    assert_client_error session,
                        CaseClauseError,
                        "no case clause matching:\n\n    3\n",
                        fn ->
                          session
                          |> visit(CasePage)
                          |> click(button("No matching clause"))
                        end
  end

  feature "error in condition", %{session: session} do
    assert_client_error session,
                        RuntimeError,
                        "my message",
                        fn ->
                          session
                          |> visit(CasePage)
                          |> click(button("Error in condition"))
                        end
  end

  feature "error_in_clause_body", %{session: session} do
    assert_client_error session,
                        ArgumentError,
                        "my message",
                        fn ->
                          session
                          |> visit(CasePage)
                          |> click(button("Error in clause body"))
                        end
  end

  feature "struct pattern with var field", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Struct pattern with var field"))
    |> assert_text(css("#result"), "42")
  end

  feature "partial struct pattern", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Partial struct pattern"))
    |> assert_text(css("#result"), ":matched")
  end

  feature "bare struct pattern", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Bare struct pattern"))
    |> assert_text(css("#result"), ":matched")
  end

  feature "struct pattern with guard", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Struct pattern with guard"))
    |> assert_text(css("#result"), "42")
  end

  feature "map vs struct pattern", %{session: session} do
    session
    |> visit(CasePage)
    |> click(button("Map vs struct pattern"))
    |> assert_text(css("#result"), ":fallback")
  end

  # TODO: expect the BEAM form, %HologramFeatureTests.StructFixture1{name: "other", value: 7},
  # once client-side struct inspect is implemented (see the "TODO: inspect structs" note on
  # Interpreter.#inspectMap/2 in assets/js/interpreter.mjs). The client renders structs as
  # plain maps for now - the same form asserted in call_graph/dynamic_dispatch_test.exs.
  feature "unmatched struct pattern", %{session: session} do
    assert_client_error session,
                        CaseClauseError,
                        ~s(no case clause matching:\n\n    %{__struct__: HologramFeatureTests.StructFixture1, name: "other", value: 7}\n),
                        fn ->
                          session
                          |> visit(CasePage)
                          |> click(button("Unmatched struct pattern"))
                        end
  end
end
