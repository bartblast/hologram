defmodule Hologram.ExJsConsistency.Erlang.MathTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/math_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "ceil/1" do
    test "rounds positive float with fractional part up" do
      assert :math.ceil(1.23) == 2.0
    end

    test "rounds negative float with fractional part up toward zero" do
      assert :math.ceil(-1.23) == -1.0
    end

    test "keeps positive float without fractional part unchanged" do
      assert :math.ceil(1.0) == 1.0
    end

    test "keeps negative float without fractional part unchanged" do
      assert :math.ceil(-1.0) == -1.0
    end

    test "keeps signed negative zero float unchanged" do
      assert :math.ceil(-0.0) == -0.0
    end

    test "keeps signed positive zero float unchanged" do
      assert :math.ceil(+0.0) == +0.0
    end

    test "keeps unsigned zero float unchanged" do
      assert :math.ceil(0.0) == 0.0
    end

    test "converts positive integer to float" do
      assert :math.ceil(1) == 1.0
    end

    test "converts negative integer to float" do
      assert :math.ceil(-1) == -1.0
    end

    test "converts zero integer to float" do
      assert :math.ceil(0) == 0.0
    end

    test "raises ArgumentError if the argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:math, :ceil, [:abc]}
    end
  end

  describe "exp/1" do
    test "positive float" do
      number = 2.0

      result = :math.exp(number)
      expected = 7.38905609893065

      assert result == expected
    end

    test "negative float" do
      number = -2.0

      result = :math.exp(number)
      expected = 0.1353352832366127

      assert result == expected
    end

    test "one float" do
      number = 1.0

      result = :math.exp(number)
      expected = 2.718281828459045

      assert result == expected
    end

    test "unsigned zero float" do
      number = 0.0

      result = :math.exp(number)
      expected = 1.0

      assert result == expected
    end

    test "positive zero float" do
      number = +0.0

      result = :math.exp(number)
      expected = 1.0

      assert result == expected
    end

    test "negative zero float" do
      number = -0.0

      result = :math.exp(number)
      expected = 1.0

      assert result == expected
    end

    test "positive integer" do
      number = 2

      result = :math.exp(number)
      expected = 7.38905609893065

      assert result == expected
    end

    test "negative integer" do
      number = -2

      result = :math.exp(number)
      expected = 0.1353352832366127

      assert result == expected
    end

    test "one integer" do
      number = 1

      result = :math.exp(number)
      expected = 2.718281828459045

      assert result == expected
    end

    test "zero integer" do
      number = 0

      result = :math.exp(number)
      expected = 1.0

      assert result == expected
    end

    test "integer below Number.MIN_SAFE_INTEGER" do
      # Number.MIN_SAFE_INTEGER = -9_007_199_254_740_991
      number = -9_007_199_254_740_992

      result = :math.exp(number)
      expected = 0.0

      assert result == expected
    end

    # The overflow threshold is ln(Number.MAX_VALUE) ≈ 709.782712893384
    test "largest float before overflow" do
      result = :math.exp(709.782)

      assert result == 1.796_412_028_020_638_7e308
    end

    # The overflow threshold is ln(Number.MAX_VALUE) ≈ 709.782712893384
    test "smallest float that overflows" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression",
                   {:math, :exp, [709.783]}
    end

    test "non-number argument" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:math, :exp, [:abc]}
    end
  end

  describe "floor/1" do
    test "rounds positive float with fractional part down" do
      assert :math.floor(1.23) == 1.0
    end

    test "rounds negative float with fractional part down" do
      assert :math.floor(-1.23) == -2.0
    end

    test "keeps positive float without fractional part unchanged" do
      assert :math.floor(1.0) == 1.0
    end

    test "keeps negative float without fractional part unchanged" do
      assert :math.floor(-1.0) == -1.0
    end

    test "keeps signed negative zero float unchanged" do
      assert :math.floor(-0.0) == -0.0
    end

    test "keeps signed positive zero float unchanged" do
      assert :math.floor(+0.0) == +0.0
    end

    test "keeps unsigned zero float unchanged" do
      assert :math.floor(0.0) == 0.0
    end

    test "converts positive integer to float" do
      assert :math.floor(1) == 1.0
    end

    test "converts negative integer to float" do
      assert :math.floor(-1) == -1.0
    end

    test "convets zero integer to float" do
      assert :math.floor(0) == 0.0
    end

    test "raises ArgumentError if the argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:math, :floor, [:abc]}
    end
  end

  describe "log/1" do
    test "positive float" do
      number = 2.0

      result = :math.log(number)
      expected = 0.6931471805599453

      assert result == expected
    end

    test "one float" do
      number = 1.0

      result = :math.log(number)
      expected = 0.0

      assert result == expected
    end

    test "Euler's number float" do
      number = 2.718281828459045

      result = :math.log(number)
      expected = 1.0

      assert result == expected
    end

    test "positive integer" do
      number = 2

      result = :math.log(number)
      expected = 0.6931471805599453

      assert result == expected
    end

    test "one integer" do
      number = 1

      result = :math.log(number)
      expected = 0.0

      assert result == expected
    end

    test "integer above Number.MAX_SAFE_INTEGER" do
      # Number.MAX_SAFE_INTEGER = 9_007_199_254_740_991
      number = 9_007_199_254_740_992

      result = :math.log(number)
      expected = 36.7368005696771

      assert result == expected
    end

    test "negative float" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression",
                   {:math, :log, [-2.0]}
    end

    test "unsigned zero float" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression",
                   {:math, :log, [0.0]}
    end

    test "positive signed zero float" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression",
                   {:math, :log, [+0.0]}
    end

    test "negative signed zero float" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression",
                   {:math, :log, [-0.0]}
    end

    test "negative integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression",
                   {:math, :log, [-2]}
    end

    test "integer below Number.MIN_SAFE_INTEGER" do
      # Number.MIN_SAFE_INTEGER = -9_007_199_254_740_991
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression",
                   {:math, :log, [-9_007_199_254_740_992]}
    end

    test "zero integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression",
                   {:math, :log, [0]}
    end

    test "non-number argument" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:math, :log, [:abc]}
    end
  end

  describe "pow/2" do
    test "returns base integer value raised to exponent integer value" do
      assert :math.pow(7, 3) == 343.0
    end

    test "returns base integer value raised to exponent float value" do
      assert :math.pow(4, 0.5) == 2.0
    end

    test "returns base float value raised to exponent integer value" do
      assert :math.pow(2.5, 2) == 6.25
    end

    test "returns base float value raised to exponent float value" do
      assert :math.pow(9.0, 0.5) == 3.0
    end

    test "returns negative base integer value raised to integer exponent" do
      assert :math.pow(-2, 3) == -8.0
    end

    test "returns negative base integer value raised to float exponent with no fractional part" do
      assert :math.pow(-2, 3.0) == -8.0
    end

    test "returns negative base float value raised to integer exponent" do
      assert :math.pow(-2.5, 2) == 6.25
    end

    test "returns base value raised to zero exponent" do
      assert :math.pow(7, 0) == 1.0
    end

    test "returns zero base raised to zero exponent" do
      assert :math.pow(0, 0) == 1.0
    end

    test "returns zero base raised to positive exponent" do
      assert :math.pow(0, 5) == 0.0
    end

    test "returns base value raised to negative integer exponent" do
      assert :math.pow(2, -3) == 0.125
    end

    test "returns base value raised to negative float exponent" do
      assert :math.pow(4, -0.5) == 0.5
    end

    test "raises ArgumentError if the first argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:math, :pow, [:abc, 3]}
    end

    test "raises ArgumentError if the second argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a number"),
                   {:math, :pow, [7, :abc]}
    end

    test "raises ArithmeticError if the base is less than zero and exponent has a fractional part" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression",
                   {:math, :pow, [-7, 0.5]}
    end
  end
end
