defmodule HologramFeatureTests.ControlFlow.TryTest do
  @moduledoc """
  These scenarios are confirmed against real Elixir by the consistency tests in test/elixir/hologram/ex_js_consistency/try_test.exs (paired with the JavaScript try() / asyncTry() tests in test/javascript/interpreter_test.mjs).
  Keep them in sync.
  """
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ControlFlow.TryPage

  describe "rescue clauses" do
    feature "without a module", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Rescue without a module"))
      |> assert_text(css("#result"), ":rescued_any")
    end

    feature "with a single module", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Rescue with a single module"))
      |> assert_text(css("#result"), ~s/{:rescued_single, "my message"}/)
    end

    feature "with multiple modules", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Rescue with multiple modules"))
      |> assert_text(css("#result"), ~s/{:rescued_multiple, "my message"}/)
    end

    feature "unmatched module re-raises", %{session: session} do
      assert_client_error session,
                          RuntimeError,
                          "my message",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("Rescue unmatched module"))
                          end
    end

    feature "bare reason is normalized into an exception struct", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Rescue bare reason"))
      |> assert_text(css("#result"), ~s/{:rescued_normalized, "argument error"}/)
    end

    feature "reraise re-raises the rescued exception", %{session: session} do
      # Asserts only the re-raised exception. The matching consistency test
      # additionally asserts that reraise preserves the original raise-site
      # stacktrace, which is server-only - the client has no stacktraces yet
      # (__STACKTRACE__ is []), so there is nothing to preserve here.
      #
      # TODO: once client-side stacktraces are supported (see the TODO in
      # lib/hologram/compiler/transformer.ex), tighten this to also assert that
      # reraise preserves the original raise-site stacktrace, mirroring the
      # consistency test.
      assert_client_error session,
                          ArgumentError,
                          "my message",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("Rescue reraise"))
                          end
    end
  end

  describe "catch clauses" do
    feature "throw kind", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Catch throw"))
      |> assert_text(css("#result"), ~s/{:caught_throw, "my value"}/)
    end

    feature "exit kind", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Catch exit"))
      |> assert_text(css("#result"), ~s/{:caught_exit, "my reason"}/)
    end

    feature "error kind", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Catch error"))
      |> assert_text(css("#result"), ~s/{:caught_error, "my message"}/)
    end

    feature "unmatched kind re-raises", %{session: session} do
      assert_client_error session,
                          RuntimeError,
                          "my message",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("Catch unmatched kind"))
                          end
    end
  end

  describe "__STACKTRACE__" do
    # CLIENT/SERVER DIVERGENCE: the client does not support stacktraces yet, so
    # __STACKTRACE__ is compiled to an empty list. The consistency test
    # (test/elixir/hologram/ex_js_consistency/try_test.exs "__STACKTRACE__ holds the
    # stacktrace pointing to where the error was raised") asserts the real, non-empty
    # server stacktrace instead.
    #
    # TODO: support real client-side stacktraces so this matches the consistency
    # test. Maintain a call stack in the interpreter (push a frame per function
    # call), capture it when a HologramBoxedError is raised, and bind __STACKTRACE__
    # to that captured trace within rescue/catch clause scopes, instead of compiling
    # it to an empty list in lib/hologram/compiler/transformer.ex.
    feature "evaluates to an empty list on the client", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Stacktrace"))
      |> assert_text(css("#result"), ~s/{:stacktrace, []}/)
    end
  end

  describe "else clauses" do
    feature "matches the do result", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Else with a match"))
      |> assert_text(css("#result"), ":else_two")
    end

    feature "raises TryClauseError when no clause matches", %{session: session} do
      assert_client_error session,
                          TryClauseError,
                          "no try clause matching:\n\n    :no_match\n",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("Else without a match"))
                          end
    end
  end

  describe "after block" do
    feature "keeps the do result", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("After keeps result"))
      |> assert_text(css("#result"), ":body_result")
    end

    feature "runs on the success path", %{session: session} do
      assert_client_error session,
                          RuntimeError,
                          "after ran",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("After runs on success"))
                          end
    end

    feature "runs on the failure path", %{session: session} do
      assert_client_error session,
                          RuntimeError,
                          "after ran",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("After runs on failure"))
                          end
    end
  end

  describe "variable scoping" do
    feature "do block bindings do not leak", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Do block vars do not leak"))
      |> assert_text(css("#result"), "{1, 2}")
    end

    feature "clause bindings do not leak", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Clause vars do not leak"))
      |> assert_text(css("#result"), "{1, 2}")
    end
  end
end
