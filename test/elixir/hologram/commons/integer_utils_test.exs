defmodule Hologram.Commons.IntegerUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.IntegerUtils

  test "count_digits?/1" do
    assert count_digits(123) == 3
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
      assert parse!("abc", 36) == 13368
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
