defmodule Hologram.ExJsConsistency.TryTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/interpreter_test.mjs (try() / asyncTry() sections).
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

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
