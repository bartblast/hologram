defmodule Hologram.ExJsConsistency.TryTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/interpreter_test.mjs (try() / asyncTry() sections).
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "rescue clauses" do
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
  end

  describe "else clauses" do
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
end
