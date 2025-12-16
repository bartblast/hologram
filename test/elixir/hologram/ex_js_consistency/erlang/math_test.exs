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
end
