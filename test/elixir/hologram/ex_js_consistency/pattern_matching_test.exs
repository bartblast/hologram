defmodule Hologram.ExJsConsistency.PatternMatchingTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related Javascript test in test/javascript/interpreter_test.mjs (matchOperator() tests)
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  defp build_match_operator(left, right) do
    ^left = right
  end

  describe "atom type" do
    test "left atom == right atom" do
      result = build_match_operator(:abc, :abc)
      assert result == :abc
    end

    test "left atom != right atom" do
      assert_raise MatchError, "no match of right hand side value: :xyz", fn ->
        build_match_operator(:abc, :xyz)
      end
    end

    test "left atom != right non-atom" do
      assert_raise MatchError, "no match of right hand side value: 2", fn ->
        build_match_operator(:abc, 2)
      end
    end
  end
end
