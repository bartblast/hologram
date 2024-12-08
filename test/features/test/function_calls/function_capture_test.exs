defmodule HologramFeatureTests.FunctionCalls.FunctionCaptureTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.FunctionCalls.FunctionCapturePage

  # IMPORTANT!
  # Keep consistent with Elixir/JavaScript consistency tests
  # in test/elixir/hologram/ex_js_consistency/interpreter_test.exs (call function capture section).

  feature "single arg", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Single arg"))
    |> assert_text(css("#result"), ":a")
  end

  feature "multiple args", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Multiple args"))
    |> assert_text(css("#result"), "{:a, :b}")
  end

  feature "local private function capture", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Local private function capture"))
    |> assert_text(css("#result"), "{:a, :b}")
  end

  feature "local public function capture", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Local public function capture"))
    |> assert_text(css("#result"), "{:a, :b}")
  end

  feature "remote private Elixir function capture", %{session: session} do
    assert_client_error session,
                        UndefinedFunctionError,
                        "function HologramFeatureTests.ModuleFixture1.private_fun/2 is undefined or private",
                        fn ->
                          session
                          |> visit(FunctionCapturePage)
                          |> click(button("Remote private Elixir function capture"))
                        end
  end

  feature "remote public Elixir function capture", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Remote public Elixir function capture"))
    |> assert_text(css("#result"), "{:a, :b}")
  end

  feature "remote Erlang function capture", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Remote Erlang function capture"))
    |> assert_text(css("#result"), "true")
  end

  feature "partially applied local function capture", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Partially applied local function capture"))
    |> assert_text(css("#result"), "{:a, :b}")
  end

  feature "partially applied remote Elixir function capture", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Partially applied remote Elixir function capture"))
    |> assert_text(css("#result"), "{:a, :b}")
  end

  feature "partially applied remote Erlang function capture", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Partially applied remote Erlang function capture"))
    |> assert_text(css("#result"), "true")
  end

  feature "vars scoping", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Vars scoping"))
    |> assert_text(css("#result"), "{1, 2, {3, 4, 2}}")
  end

  feature "closure", %{session: session} do
    session
    |> visit(FunctionCapturePage)
    |> click(button("Closure"))
    |> assert_text(css("#result"), "{3, 4, {5, 1, 2}}")
  end

  # TODO: client error message for this case is inconsistent with server error message
  feature "arity invalid, called with no args", %{session: session} do
    assert_client_error session,
                        BadArityError,
                        "anonymous function with arity 2 called with no arguments",
                        fn ->
                          session
                          |> visit(FunctionCapturePage)
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
                          |> visit(FunctionCapturePage)
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
                          |> visit(FunctionCapturePage)
                          |> click(button("Arity invalid, called with multiple args"))
                        end
  end

  feature "Error in body", %{session: session} do
    assert_client_error session,
                        RuntimeError,
                        "my message",
                        fn ->
                          session
                          |> visit(FunctionCapturePage)
                          |> click(button("Error in body"))
                        end
  end
end
