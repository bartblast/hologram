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
      assert :math.ceil(-0.0) == 0.0
    end

    test "keeps signed positive zero float unchanged" do
      assert :math.ceil(+0.0) == 0.0
    end

    test "keeps unsigned zero float unchanged" do
      assert :math.ceil(0.0) == 0.0
    end

    test "keeps positive integer unchanged" do
      assert :math.ceil(1) == 1.0
    end

    test "keeps negative integer unchanged" do
      assert :math.ceil(-1) == -1.0
    end

    test "keeps zero integer unchanged" do
      assert :math.ceil(0) == 0.0
    end

    test "raises ArgumentError if the argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:math, :ceil, [:abc]}
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
      assert :math.floor(-0.0) == 0.0
    end

    test "keeps signed positive zero float unchanged" do
      assert :math.floor(+0.0) == 0.0
    end

    test "keeps unsigned zero float unchanged" do
      assert :math.floor(0.0) == 0.0
    end

    test "keeps positive integer unchanged" do
      assert :math.floor(1) == 1.0
    end

    test "keeps negative integer unchanged" do
      assert :math.floor(-1) == -1.0
    end

    test "keeps zero integer unchanged" do
      assert :math.floor(0) == 0.0
    end

    test "raises ArgumentError if the argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:math, :floor, [:abc]}
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
