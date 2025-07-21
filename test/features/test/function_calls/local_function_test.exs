defmodule HologramFeatureTests.FunctionCalls.LocalFunctionTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.FunctionCalls.LocalFunctionPage

  # IMPORTANT!
  # Keep consistent with Elixir/JavaScript consistency tests
  # in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call local function section).

  # public function / no args / single clause / single-expression body
  feature "basic case", %{session: session} do
    session
    |> visit(LocalFunctionPage)
    |> click(button("Basic case"))
    |> assert_text(css("#result"), ":a")
  end

  feature "private function", %{session: session} do
    session
    |> visit(LocalFunctionPage)
    |> click(button("Private function"))
    |> assert_text(css("#result"), ":a")
  end

  feature "single arg", %{session: session} do
    session
    |> visit(LocalFunctionPage)
    |> click(button("Single arg"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple args", %{session: session} do
    session
    |> visit(LocalFunctionPage)
    |> click(button("Multiple args"))
    |> assert_text(css("#result"), "{:a, :b}")
  end

  feature "multiple clauses", %{session: session} do
    session
    |> visit(LocalFunctionPage)
    |> click(button("Multiple clauses"))
    |> assert_text(css("#result"), "{2, :a}")
  end

  feature "multiple-expression body", %{session: session} do
    session
    |> visit(LocalFunctionPage)
    |> click(button("Multiple-expression body"))
    |> assert_text(css("#result"), ":b")
  end

  feature "vars scoping", %{session: session} do
    session
    |> visit(LocalFunctionPage)
    |> click(button("Vars scoping"))
    |> assert_text(css("#result"), "{1, 2, {11, 5}}")
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "no matching clause", %{session: session} do
    assert_client_error session,
                        FunctionClauseError,
                        build_function_clause_error_msg(
                          "HologramFeatureTests.FunctionCalls.LocalFunctionPage.local_fun_4/2",
                          [4, 5]
                        ),
                        fn ->
                          session
                          |> visit(LocalFunctionPage)
                          |> click(button("No matching clause"))
                        end
  end

  feature "Error in body", %{session: session} do
    assert_client_error session,
                        RuntimeError,
                        "my message",
                        fn ->
                          session
                          |> visit(LocalFunctionPage)
                          |> click(button("Error in body"))
                        end
  end
end
