defmodule Hologram.ExJsConsistency.Erlang.BinaryToFloatTest do
  use Hologram.Test.BasicCase, async: true
  @moduletag :consistency

  describe "binary_to_float/1" do
    # -------------------------
    # Success Cases
    # -------------------------

    test "converts a correct binary to a float" do
      result = :erlang.binary_to_float("10.5")
      assert result == 10.5
    end

    test "parses scientific notation" do
      result = :erlang.binary_to_float("2.2017764e+1")
      assert result == 22.017764
    end

    test "parses negative float" do
      result = :erlang.binary_to_float("-3.14")
      assert result == -3.14
    end

    test "parses float with leading zeros" do
      result = :erlang.binary_to_float("00012.34")
      assert result == 12.34
    end

    test "parses + sign float" do
      result = :erlang.binary_to_float("+15.5")
      assert result == 15.5
    end

    test "parses uppercase E scientific notation" do
      result = :erlang.binary_to_float("1.2E3")
      assert result == 1200.0
    end

    test "parses negative exponent" do
      result = :erlang.binary_to_float("1.23e-3")
      assert result == 0.00123
    end

    # -------------------------
    # Error Cases
    # -------------------------

    test "raises argument error if input is not a binary" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float(123)
      end
    end

    test "raises badarg when float contains underscores" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("1_000.5")
      end
    end

    test "raises badarg for invalid float format" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("12.3.4")
      end
    end

    test "raises badarg for non-numeric text" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("abc")
      end
    end

    test "rejects empty binary" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("")
      end
    end

    test "rejects decimal point only" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float(".")
      end
    end

    test "rejects leading dot such as .5" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float(".5")
      end
    end

    test "rejects trailing dot such as 5." do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("5.")
      end
    end

    test "rejects scientific notation without a fraction like 3e10" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("3e10")
      end
    end

    test "raises badarg on trailing exponent marker" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("2e")
      end
    end

    test "raises badarg on whitespace around the number" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float(" 12.3")
      end
    end

    test "raises badarg on multiple exponent markers" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("1e2e3")
      end
    end

    test "raises badarg on Infinity text" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("Infinity")
      end
    end

    test "raises badarg on hex-style JS float" do
      assert_raise ArgumentError, fn ->
        :erlang.binary_to_float("0x1.fp2")
      end
    end
  end
end
