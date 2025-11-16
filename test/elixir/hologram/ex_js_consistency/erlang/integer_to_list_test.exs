defmodule Hologram.ExJsConsistency.Erlang.IntegerToListTest do
  use Hologram.Test.BasicCase, async: true
  @moduletag :consistency

  describe "integer_to_list/1" do
    test "positive integer" do
      assert :erlang.integer_to_list(77) == '77'
    end

    test "negative integer" do
      assert :erlang.integer_to_list(-123) == '-123'
    end

    test "zero" do
      assert :erlang.integer_to_list(0) == '0'
    end

    test "large integer" do
      big = 12_345_678_901_234_567_890
      assert :erlang.integer_to_list(big) == '12345678901234567890'
    end

    test "does not generate leading plus sign" do
      assert :erlang.integer_to_list(+10) == '10'
    end

    test "negative zero outputs '0'" do
      assert :erlang.integer_to_list(-0) == '0'
    end

    test "raises error for non-integer" do
      assert_raise ArgumentError, fn ->
        :erlang.integer_to_list(3.14)
      end
    end
  end

  describe "integer_to_list/2" do
    test "base 10 standard conversion" do
      assert :erlang.integer_to_list(1234, 10) == '1234'
    end

    test "base 2 (binary)" do
      assert :erlang.integer_to_list(10, 2) == '1010'
    end

    test "base 16 (hex uppercase)" do
      assert :erlang.integer_to_list(1023, 16) == '3FF'
    end

    test "base 36 upper boundary" do
      assert :erlang.integer_to_list(35, 36) == 'Z'
      assert :erlang.integer_to_list(36, 36) == '10'
    end

    test "base 2 lower boundary" do
      assert :erlang.integer_to_list(1, 2) == '1'
    end

    test "negative integer in base 2" do
      assert :erlang.integer_to_list(-10, 2) == '-1010'
    end

    test "negative integer in base 16" do
      assert :erlang.integer_to_list(-255, 16) == '-FF'
    end

    test "large integer with base conversion" do
      big = 4_294_967_295
      assert :erlang.integer_to_list(big, 16) == 'FFFFFFFF'
    end

    test "zero with any base" do
      assert :erlang.integer_to_list(0, 2) == '0'
      assert :erlang.integer_to_list(0, 36) == '0'
    end

    test "large negative integer with base conversion" do
      assert :erlang.integer_to_list(-4_294_967_295, 16) == '-FFFFFFFF'
    end

    test "negative integer with base 36" do
      assert :erlang.integer_to_list(-35, 36) == '-Z'
    end

    # ----------- error cases -------------

    test "raises error for base < 2" do
      assert_raise ArgumentError, fn ->
        :erlang.integer_to_list(10, 1)
      end
    end

    test "raises error for base > 36" do
      assert_raise ArgumentError, fn ->
        :erlang.integer_to_list(10, 37)
      end
    end

    test "raises error when first arg is not integer" do
      assert_raise ArgumentError, fn ->
        :erlang.integer_to_list(3.14, 10)
      end
    end

    test "raises error when second arg is not integer" do
      assert_raise ArgumentError, fn ->
        :erlang.integer_to_list(10, 3.5)
      end
    end

    test "raises when first argument is float even with valid base" do
      assert_raise ArgumentError, fn ->
        :erlang.integer_to_list(12.0, 16)
      end
    end
  end
end
