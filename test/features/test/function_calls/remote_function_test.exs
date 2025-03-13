defmodule HologramFeatureTests.FunctionCalls.RemoteFunctionTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.FunctionCalls.RemoteFunctionPage

  # IMPORTANT!
  # Keep consistent with Elixir/JavaScript consistency tests
  # in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call remote function section).

  # public function / Elixir function / no args / single clause / single-expression body
  feature "basic case", %{session: session} do
    session
    |> visit(RemoteFunctionPage)
    |> click(button("Basic case"))
    |> assert_text(css("#result"), ":a")
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "private function", %{session: session} do
    assert_client_error session,
                        UndefinedFunctionError,
                        build_undefined_function_error(
                          {HologramFeatureTests.ModuleFixture2, :fun_2, 0},
                          []
                        ),
                        fn ->
                          session
                          |> visit(RemoteFunctionPage)
                          |> click(button("Private function"))
                        end
  end

  feature "Erlang function", %{session: session} do
    session
    |> visit(RemoteFunctionPage)
    |> click(button("Erlang function"))
    |> assert_text(css("#result"), "1")
  end

  feature "single arg", %{session: session} do
    session
    |> visit(RemoteFunctionPage)
    |> click(button("Single arg"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple args", %{session: session} do
    session
    |> visit(RemoteFunctionPage)
    |> click(button("Multiple args"))
    |> assert_text(css("#result"), "{:a, :b}")
  end

  feature "multiple clauses", %{session: session} do
    session
    |> visit(RemoteFunctionPage)
    |> click(button("Multiple clauses"))
    |> assert_text(css("#result"), "{2, :a}")
  end

  feature "multiple-expression body", %{session: session} do
    session
    |> visit(RemoteFunctionPage)
    |> click(button("Multiple-expression body"))
    |> assert_text(css("#result"), ":b")
  end

  feature "vars scoping", %{session: session} do
    session
    |> visit(RemoteFunctionPage)
    |> click(button("Vars scoping"))
    |> assert_text(css("#result"), "{1, 2, {11, 5}}")
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "arity invalid, called with no args", %{session: session} do
    assert_client_error session,
                        UndefinedFunctionError,
                        build_undefined_function_error(
                          {HologramFeatureTests.ModuleFixture2, :fun_4, 0},
                          []
                        ),
                        fn ->
                          session
                          |> visit(RemoteFunctionPage)
                          |> click(button("Arity invalid, called with no args"))
                        end
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "arity invalid, called with single arg", %{session: session} do
    assert_client_error session,
                        UndefinedFunctionError,
                        build_undefined_function_error(
                          {HologramFeatureTests.ModuleFixture2, :fun_4, 1},
                          []
                        ),
                        fn ->
                          session
                          |> visit(RemoteFunctionPage)
                          |> click(button("Arity invalid, called with single arg"))
                        end
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "arity invalid, called with multiple args", %{session: session} do
    assert_client_error session,
                        UndefinedFunctionError,
                        build_undefined_function_error(
                          {HologramFeatureTests.ModuleFixture2, :fun_3, 2},
                          []
                        ),
                        fn ->
                          session
                          |> visit(RemoteFunctionPage)
                          |> click(button("Arity invalid, called with multiple args"))
                        end
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "no matching clause", %{session: session} do
    assert_client_error session,
                        FunctionClauseError,
                        build_function_clause_error_msg(
                          "HologramFeatureTests.ModuleFixture2.fun_5/2",
                          [4, 5]
                        ),
                        fn ->
                          session
                          |> visit(RemoteFunctionPage)
                          |> click(button("No matching clause"))
                        end
  end

  feature "Error in body", %{session: session} do
    assert_client_error session,
                        RuntimeError,
                        "my message",
                        fn ->
                          session
                          |> visit(RemoteFunctionPage)
                          |> click(button("Error in body"))
                        end
  end
end
