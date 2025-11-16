defmodule Hologram.ExJsConsistency.Elixir.BitwiseTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/bitwise_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "band/2 and &&&/2" do
    test "calculates bitwise AND" do
      assert Bitwise.band(9, 3) == 1
    end

    test "handles negative operands" do
      assert Bitwise.&&&(-5, 12) == Bitwise.band(-5, 12)
    end

    test "raises ArithmeticError when an operand is not an integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: Bitwise.band(:foo, 1)",
                   {Bitwise, :band, [:foo, 1]}
    end
  end

  describe "bor/2 and |||/2" do
    test "calculates bitwise OR" do
      assert Bitwise.bor(9, 3) == 11
    end

    test "supports operator form" do
      assert Bitwise.|||(-5, 12) == Bitwise.bor(-5, 12)
    end
  end

  describe "bxor/2 and ^^^/2" do
    test "calculates bitwise XOR" do
      assert Bitwise.bxor(9, 3) == 10
    end

    test "supports operator form" do
      assert Bitwise.^^^(-5, 12) == Bitwise.bxor(-5, 12)
    end
  end

  describe "bnot/1 and ~~~/1" do
    test "calculates bitwise NOT" do
      assert Bitwise.bnot(2) == -3
    end

    test "supports operator form" do
      assert Bitwise.~~~(-1) == Bitwise.bnot(-1)
    end
  end

  describe "bsl/2 and <<</2" do
    test "shifts left for positive shift counts" do
      assert Bitwise.bsl(1, 3) == 8
    end

    test "converts negative shift counts to right shifts" do
      assert Bitwise.bsl(1, -2) == 0
    end

    test "supports operator form" do
      assert Bitwise.<<<(-1, 2) == Bitwise.bsl(-1, 2)
    end
  end

  describe "bsr/2 and >>>/2" do
    test "shifts right for positive shift counts" do
      assert Bitwise.bsr(9, 2) == 2
    end

    test "converts negative shift counts to left shifts" do
      assert Bitwise.bsr(1, -2) == 4
    end

    test "supports operator form" do
      assert Bitwise.>>>(-8, 2) == Bitwise.bsr(-8, 2)
    end
  end
end
