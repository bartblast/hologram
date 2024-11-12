defmodule Hologram.Commons.IntegerUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.IntegerUtils

  test "count_digits?/1" do
    assert count_digits(123) == 3
  end

  describe "ordinal/1" do
    test "0th" do
      assert ordinal(0) == "0th"
    end

    test "1st" do
      assert ordinal(1) == "1st"
    end

    test "2nd" do
      assert ordinal(2) == "2nd"
    end

    test "3rd" do
      assert ordinal(3) == "3rd"
    end

    test "4th" do
      assert ordinal(4) == "4th"
    end

    test "5th" do
      assert ordinal(5) == "5th"
    end

    test "10th" do
      assert ordinal(10) == "10th"
    end

    test "11th" do
      assert ordinal(11) == "11th"
    end

    test "12th" do
      assert ordinal(12) == "12th"
    end

    test "13th" do
      assert ordinal(13) == "13th"
    end

    test "14th" do
      assert ordinal(14) == "14th"
    end

    test "15th" do
      assert ordinal(15) == "15th"
    end

    test "20th" do
      assert ordinal(20) == "20th"
    end

    test "21st" do
      assert ordinal(21) == "21st"
    end

    test "22nd" do
      assert ordinal(22) == "22nd"
    end

    test "23rd" do
      assert ordinal(23) == "23rd"
    end

    test "24th" do
      assert ordinal(24) == "24th"
    end

    test "25th" do
      assert ordinal(25) == "25th"
    end

    test "100th" do
      assert ordinal(100) == "100th"
    end

    test "101st" do
      assert ordinal(101) == "101st"
    end

    test "102nd" do
      assert ordinal(102) == "102nd"
    end

    test "103rd" do
      assert ordinal(103) == "103rd"
    end

    test "104th" do
      assert ordinal(104) == "104th"
    end

    test "105th" do
      assert ordinal(105) == "105th"
    end
  end

  describe "parse!/2" do
    test "base 1" do
      assert_raise ArgumentError, "invalid base 1", fn ->
        parse!("123", 1)
      end
    end

    test "base 2" do
      assert parse!("1010", 2) == 10
    end

    test "base 10 (default)" do
      assert parse!("123") == 123
    end

    test "base 36" do
      assert parse!("abc", 36) == 13_368
    end

    test "base 37" do
      assert_raise ArgumentError, "invalid base 37", fn ->
        parse!("abc", 37)
      end
    end

    test "invalid text representation" do
      assert_raise ArgumentError, "invalid text representation", fn ->
        parse!("abc", 10)
      end
    end

    test "only part of the text representation can be parsed" do
      assert_raise ArgumentError, "only part of the text representation can be parsed", fn ->
        parse!("123abc", 10)
      end
    end
  end
end
