defmodule Hologram.ExJsConsistency.MatchOperatorTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/interpreter_test.mjs (matchOperator() section)
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  # The build_match_operator/2 and build_value/1 helpers
  # prevent warnings about incompatible types.

  defp build_match_operator(left, right) do
    ^left = right
  end

  defp build_value(value) do
    value
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

  describe "cons pattern" do
    test "left cons pattern == right list, cons pattern head and tail are variables" do
      result = [h | t] = [1, 2, 3]

      assert result == [1, 2, 3]
      assert h == 1
      assert t == [2, 3]
    end

    test "left cons pattern == right list, cons pattern head is variable, tail is literal" do
      result = [h | [2, 3]] = [1, 2, 3]

      assert result == [1, 2, 3]
      assert h == 1
    end

    test "left cons pattern == right list, cons pattern head is literal, tail is variable" do
      result = [1 | t] = [1, 2, 3]

      assert result == [1, 2, 3]
      assert t == [2, 3]
    end

    test "left cons pattern == right list, cons pattern head and tail are literals" do
      result = [1 | [2, 3]] = [1, 2, 3]

      assert result == [1, 2, 3]
    end

    test "raises match error if right is not a boxed list" do
      assert_raise MatchError, "no match of right hand side value: 123", fn ->
        [_h | _t] = build_value(123)
      end
    end

    test "raises match error if right is an empty boxed list" do
      assert_raise MatchError, "no match of right hand side value: []", fn ->
        [_h | _t] = build_value([])
      end
    end

    test "raises match error if head doesn't match" do
      assert_raise MatchError, "no match of right hand side value: [1, 2, 3]", fn ->
        [4 | [2, 3]] = build_value([1, 2, 3])
      end
    end

    test "raises match error if tail doesn't match" do
      assert_raise MatchError, "no match of right hand side value: [1, 2, 3]", fn ->
        [1 | [4, 3]] = build_value([1, 2, 3])
      end
    end
  end
end
