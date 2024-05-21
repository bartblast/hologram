defmodule Hologram.Commons.BitstringUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.BitstringUtils

  describe "from_bit_list/1" do
    test "starting with 1" do
      assert from_bit_list([1, 0, 1, 0]) == <<1::1, 0::1, 1::1, 0::1>>
    end

    test "starting with 0" do
      assert from_bit_list([0, 1, 0, 1]) == <<0::1, 1::1, 0::1, 1::1>>
    end
  end

  describe "to_bit_list/1" do
    test "bitstring" do
      assert to_bit_list(<<1::1, 0::1, 1::1, 0::1>>) == [1, 0, 1, 0]
    end

    test "float" do
      assert <<123.45>> == <<64, 94, 220, 204, 204, 204, 204, 205>>

      # 64 == 0b01000000
      # 94 == 0b01011110
      # 220 == 0b11011100
      # 204 == 0b11001100
      # 204 == 0b11001100
      # 204 == 0b11001100
      # 204 == 0b11001100
      # 205 == 0b11001101

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          0, 1, 0, 0, 0, 0, 0, 0,
          0, 1, 0, 1, 1, 1, 1, 0,
          1, 1, 0, 1, 1, 1, 0, 0,
          1, 1, 0, 0, 1, 1, 0, 0,
          1, 1, 0, 0, 1, 1, 0, 0,
          1, 1, 0, 0, 1, 1, 0, 0,
          1, 1, 0, 0, 1, 1, 0, 0,
          1, 1, 0, 0, 1, 1, 0, 1
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(<<123.45>>) == bits
    end

    test "4-bit integer" do
      assert 0b1010 == 10
      assert to_bit_list(<<10::4>>) == [1, 0, 1, 0]
    end

    test "12-bit integer" do
      assert 0b101010101010 == 2_730
      assert to_bit_list(<<2_730::12>>) == [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "string" do
      assert <<"abc">> == <<97, 98, 99>>

      # 97 == 0b01100001
      # 98 == 0b01100010
      # 99 == 0b01100011

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          0, 1, 1, 0, 0, 0, 0, 1,
          0, 1, 1, 0, 0, 0, 1, 0,
          0, 1, 1, 0, 0, 0, 1, 1
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(<<"abc">>) == bits
    end
  end
end
