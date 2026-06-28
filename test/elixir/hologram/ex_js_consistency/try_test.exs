defmodule Hologram.ExJsConsistency.TryTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/interpreter_test.mjs (try() / asyncTry() sections).
  Always update both together.

  These scenarios also mirror the try feature tests in test/features/test/control_flow/try_test.exs (page: test/features/app/pages/control_flow/try_page.ex).
  Keep them in sync.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "rescue clauses" do
    test "rescues a bare reason normalized into an exception struct" do
      result =
        try do
          :erlang.error(:badarg)
        rescue
          e in ArgumentError -> {:rescued_normalized, e.message}
        end

      assert result == {:rescued_normalized, "argument error"}
    end

    test "rescues without a module" do
      result =
        try do
          raise RuntimeError, "my message"
        rescue
          _exception -> :rescued_any
        end

      assert result == :rescued_any
    end

    test "rescues with a single module" do
      result =
        try do
          raise ArgumentError, "my message"
        rescue
          e in ArgumentError -> {:rescued_single, e.message}
        end

      assert result == {:rescued_single, "my message"}
    end

    test "rescues with multiple modules" do
      result =
        try do
          raise RuntimeError, "my message"
        rescue
          e in [ArgumentError, RuntimeError] -> {:rescued_multiple, e.message}
        end

      assert result == {:rescued_multiple, "my message"}
    end

    test "re-raises when no rescue clause matches" do
      assert_error RuntimeError, "my message", fn ->
        try do
          raise RuntimeError, "my message"
        rescue
          e in ArgumentError -> {:rescued_single, e.message}
        end
      end
    end

    test "reraise re-raises the rescued exception" do
      # reraise/2 must preserve the stacktrace of the original raise site, not the
      # rescue clause that re-raises. The outer try captures the re-raised error
      # together with its stacktrace.
      #
      # CLIENT/SERVER DIVERGENCE: the stacktrace assertion is server-only. On the
      # client reraise re-raises with __STACKTRACE__ = [] (no client stacktraces
      # yet - see the "__STACKTRACE__" describe and the TODO in
      # lib/hologram/compiler/transformer.ex), so the paired JavaScript and feature
      # tests assert only that the exception is re-raised.
      #
      # TODO: once client-side stacktraces are supported (see the TODO in
      # lib/hologram/compiler/transformer.ex), the paired JavaScript and feature
      # tests should be tightened to mirror this stacktrace-preservation assertion.
      expected_line = __ENV__.line + 5

      {error, stacktrace} =
        try do
          try do
            raise ArgumentError, "my message"
          rescue
            error -> reraise error, __STACKTRACE__
          end
        rescue
          error -> {error, __STACKTRACE__}
        end

      assert %ArgumentError{message: "my message"} = error
      assert [{__MODULE__, _function, _arity, location} | _rest] = stacktrace
      assert Keyword.fetch!(location, :line) == expected_line
    end
  end

  describe "catch clauses" do
    test "catches a throw" do
      result =
        try do
          throw("my value")
        catch
          value -> {:caught_throw, value}
        end

      assert result == {:caught_throw, "my value"}
    end

    test "catches an exit" do
      result =
        try do
          exit("my reason")
        catch
          :exit, reason -> {:caught_exit, reason}
        end

      assert result == {:caught_exit, "my reason"}
    end

    test "catches an error" do
      result =
        try do
          raise RuntimeError, "my message"
        catch
          :error, reason -> {:caught_error, reason.message}
        end

      assert result == {:caught_error, "my message"}
    end

    test "re-raises when no clause kind matches" do
      assert_error RuntimeError, "my message", fn ->
        try do
          raise RuntimeError, "my message"
        catch
          :throw, value -> {:caught_throw, value}
        end
      end
    end
  end

  describe "__STACKTRACE__" do
    # CLIENT/SERVER DIVERGENCE: on the server __STACKTRACE__ is the real stacktrace
    # asserted below, but the client does not support stacktraces yet, so it
    # compiles __STACKTRACE__ to an empty list. The related JavaScript test
    # (interpreter_test.mjs) and the try feature test therefore assert [] instead
    # of this shape - they carry a TODO pointing here, and the steps to make the
    # client match this test live in the TODO in lib/hologram/compiler/transformer.ex.
    #
    # TODO: support real client-side stacktraces so the client matches this test.
    # Maintain a call stack in the interpreter (push a frame per function call),
    # capture it when a HologramBoxedError is raised, and bind __STACKTRACE__ to that
    # captured trace within rescue/catch clause scopes, instead of compiling it to an
    # empty list in lib/hologram/compiler/transformer.ex.
    test "holds the stacktrace pointing to where the error was raised" do
      result =
        try do
          raise "boom"
        rescue
          _exception -> __STACKTRACE__
        end

      # The top frame identifies this test - the module, file, and line where
      # raise/1 was called - which proves __STACKTRACE__ captured the real call
      # stack rather than just any list of frame-shaped tuples.
      assert [{__MODULE__, _function, _arity, location} | _rest] = result

      file = to_string(Keyword.fetch!(location, :file))
      assert String.ends_with?(file, "try_test.exs")
      assert is_integer(Keyword.fetch!(location, :line))
    end
  end

  describe "else clauses" do
    test "matches the do block result against the else clauses" do
      value = wrap_term(2)

      result =
        try do
          value
        else
          1 -> :else_one
          2 -> :else_two
        after
          nil
        end

      assert result == :else_two
    end

    test "raises TryClauseError when no else clause matches" do
      value = wrap_term(:no_match)

      # An "after" clause is required because Elixir rejects an "else"-only try.
      assert_error TryClauseError, build_try_clause_error_msg(:no_match), fn ->
        try do
          value
        else
          :other -> nil
        after
          nil
        end
      end
    end
  end

  describe "after block" do
    test "keeps the do block result" do
      result =
        try do
          :body_result
        after
          :ignored
        end

      assert result == :body_result
    end

    test "propagates an error raised by the after block on the success path" do
      assert_error RuntimeError, "after ran", fn ->
        try do
          :ok
        after
          raise RuntimeError, "after ran"
        end
      end
    end

    test "an after-block error replaces the do-block error on the failure path" do
      assert_error RuntimeError, "after ran", fn ->
        try do
          raise ArgumentError, "boom"
        after
          raise RuntimeError, "after ran"
        end
      end
    end
  end

  describe "variable scoping" do
    test "do block bindings do not leak" do
      x = wrap_term(1)

      result =
        try do
          x = 2
          x
        after
          nil
        end

      assert {x, result} == {1, 2}
    end

    test "clause bindings do not leak" do
      x = wrap_term(1)

      result =
        try do
          raise RuntimeError, "boom"
        rescue
          _exception ->
            x = 2
            x
        end

      assert {x, result} == {1, 2}
    end
  end
end
