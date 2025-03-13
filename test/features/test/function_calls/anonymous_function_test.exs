defmodule HologramFeatureTests.FunctionCalls.AnonymousFunctionTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.FunctionCalls.AnonymousFunctionPage

  # IMPORTANT!
  # Keep consistent with Elixir/JavaScript consistency tests
  # in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call anonymous function section).

  # no args / single clause / single-expression body
  feature "basic case", %{session: session} do
    session
    |> visit(AnonymousFunctionPage)
    |> click(button("Basic case"))
    |> assert_text(css("#result"), ":a")
  end

  feature "single arg", %{session: session} do
    session
    |> visit(AnonymousFunctionPage)
    |> click(button("Single arg"))
    |> assert_text(css("#result"), "1")
  end

  feature "multiple args", %{session: session} do
    session
    |> visit(AnonymousFunctionPage)
    |> click(button("Multiple args"))
    |> assert_text(css("#result"), "{1, 2}")
  end

  feature "multiple clauses", %{session: session} do
    session
    |> visit(AnonymousFunctionPage)
    |> click(button("Multiple clauses"))
    |> assert_text(css("#result"), "{2, 3}")
  end

  feature "multiple-expression body", %{session: session} do
    session
    |> visit(AnonymousFunctionPage)
    |> click(button("Multiple-expression body"))
    |> assert_text(css("#result"), ":b")
  end

  feature "vars scoping", %{session: session} do
    session
    |> visit(AnonymousFunctionPage)
    |> click(button("Vars scoping"))
    |> assert_text(css("#result"), "{1, 2, 3, {15, 6, 3}}")
  end

  feature "closure", %{session: session} do
    session
    |> visit(AnonymousFunctionPage)
    |> click(button("Closure"))
    |> assert_text(css("#result"), "{3, 4, {1, 2}}")
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "arity invalid, called with no args", %{session: session} do
    assert_client_error session,
                        BadArityError,
                        "anonymous function with arity 2 called with no arguments",
                        fn ->
                          session
                          |> visit(AnonymousFunctionPage)
                          |> click(button("Arity invalid, called with no args"))
                        end
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "arity invalid, called with single arg", %{session: session} do
    assert_client_error session,
                        BadArityError,
                        "anonymous function with arity 2 called with 1 argument (:a)",
                        fn ->
                          session
                          |> visit(AnonymousFunctionPage)
                          |> click(button("Arity invalid, called with single arg"))
                        end
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "arity invalid, called with multiple args", %{session: session} do
    assert_client_error session,
                        BadArityError,
                        "anonymous function with arity 1 called with 2 arguments (:a, :b)",
                        fn ->
                          session
                          |> visit(AnonymousFunctionPage)
                          |> click(button("Arity invalid, called with multiple args"))
                        end
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "no matching clause", %{session: session} do
    assert_client_error session,
                        FunctionClauseError,
                        build_function_clause_error_msg("anonymous fn/2", [5, 6]),
                        fn ->
                          session
                          |> visit(AnonymousFunctionPage)
                          |> click(button("No matching clause"))
                        end
  end

  feature "Error in body", %{session: session} do
    assert_client_error session,
                        RuntimeError,
                        "my message",
                        fn ->
                          session
                          |> visit(AnonymousFunctionPage)
                          |> click(button("Error in body"))
                        end
  end
end
