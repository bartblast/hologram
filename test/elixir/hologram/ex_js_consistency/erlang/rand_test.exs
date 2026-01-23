defmodule Hologram.ExJsConsistency.Erlang.RandTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/rand_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "uniform/0" do
    test "returns a float in range [0.0, 1.0)" do
      result = :rand.uniform()

      assert is_float(result)
      assert result >= 0.0
      assert result < 1.0
    end
  end

  describe "uniform/1" do
    @expected_err_msg ~r'no function clause matching in :rand.uniform_s/2'

    test "positive integer argument returns integer between 1 and that argument" do
      result = :rand.uniform(10)

      assert is_integer(result)
      assert result >= 1
      assert result <= 10
    end

    test "argument 1 returns 1" do
      assert :rand.uniform(1) == 1
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if argument is a float" do
      assert_error FunctionClauseError, @expected_err_msg, fn ->
        :rand.uniform(5.5)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if argument is not a number" do
      assert_error FunctionClauseError, @expected_err_msg, fn ->
        :rand.uniform(:abc)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if argument is zero" do
      assert_error FunctionClauseError, @expected_err_msg, fn ->
        :rand.uniform(0)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if argument is negative" do
      assert_error FunctionClauseError, @expected_err_msg, fn ->
        :rand.uniform(-5)
      end
    end
  end
end
