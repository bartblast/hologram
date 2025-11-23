defmodule Hologram.ExJsConsistency.Erlang.MathTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/math_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "exp/1" do
    test "returns correct value" do
      number = 2.0

      result = :math.exp(number)
      expected = 7.38905609893065

      assert result == expected
    end

    test "returns correct value if passing negative value" do
      number = -2.0

      result = :math.exp(number)
      expected = 0.1353352832366127

      assert result == expected
    end

    test "returns correct value if passing one" do
      number = 1.0

      result = :math.exp(number)
      expected = 2.718281828459045

      assert result == expected
    end

    test "returns correct value if passing zero" do
      number = 0.0

      result = :math.exp(number)
      expected = 1.0

      assert result == expected
    end

    test "raises ArgumentError if the argument is a string" do
      integer_string = prevent_term_typing_violation("12345")

      assert_error ArgumentError,
                   ~r"errors were found at the given arguments:\n\n  \* 1st argument: not a number",
                   {:math, :exp, [integer_string]}
    end

    test "raises ArgumentError if the argument is a list" do
      list = prevent_term_typing_violation([1, 2])

      assert_error ArgumentError,
                   ~r"errors were found at the given arguments:\n\n  \* 1st argument: not a number",
                   {:math, :exp, [list]}
    end
  end
end
