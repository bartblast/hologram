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

  describe "float type" do
    test "left float == right float" do
      result = 2.0 = 2.0
      assert result == 2.0
    end

    test "left float != right float" do
      assert_raise MatchError, "no match of right hand side value: 3.0", fn ->
        2.0 = build_value(3.0)
      end
    end

    test "left float != right non-float" do
      assert_raise MatchError, "no match of right hand side value: :abc", fn ->
        2.0 = build_value(:abc)
      end
    end
  end

  describe "variable pattern" do
    test "variable pattern == anything" do
      result = x = 2

      assert result == 2
      assert x == 2
    end

    test "multiple variables with the same name being matched to the same value" do
      result = [x, x] = [1, 1]

      assert result == [1, 1]
      assert x == 1
    end

    test "multiple variables with the same name being matched to the different values" do
      assert_raise MatchError, "no match of right hand side value: [1, 2]", fn ->
        [x, x] = build_value([1, 2])
      end
    end

    test "x = 2 = 2" do
      result = x = 2 = 2

      assert result == 2
      assert x == 2
    end

    test "x = 2 = 3" do
      assert_raise MatchError, "no match of right hand side value: 3", fn ->
        _x = 2 = build_value(3)
      end
    end

    test "2 = x = 2" do
      result = 2 = x = 2

      assert result == 2
      assert x == 2
    end

    test "2 = x = 3" do
      assert_raise MatchError, "no match of right hand side value: 3", fn ->
        2 = _x = build_value(3)
      end
    end

    test "2 = 2 = x, (x = 2)" do
      x = 2
      result = 2 = 2 = x

      assert result == 2
      assert x == 2
    end

    test "2 = 2 = x, (x = 3)" do
      assert_raise MatchError, "no match of right hand side value: 3", fn ->
        x = 3
        2 = 2 = build_value(x)
      end
    end

    test "1 = 2 = x, (x = 2)" do
      assert_raise MatchError, "no match of right hand side value: 2", fn ->
        x = 2
        1 = 2 = build_value(x)
      end
    end

    test "y = x + (x = 3) + x, (x = 11)" do
      x = 11
      result = y = x + (x = 3) + x

      assert result == 25
      assert x == 3
      assert y == 25
    end
  end
end
