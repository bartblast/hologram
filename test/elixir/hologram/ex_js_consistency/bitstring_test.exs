defmodule Hologram.ExJsConsistency.BitstringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related Javascript test in test/javascript/bitstring_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.BitstringUtils, only: [to_bit_list: 1]

  describe "number and structure of segments" do
    test "builds empty bitstring without segments" do
      assert to_bit_list(<<>>) == []
    end

    test "builds single-segment bitstring" do
      assert to_bit_list(<<1::1>>) == [1]
    end

    test "builds multiple-segment bitstring" do
      assert to_bit_list(<<1::1, 1::1>>) == [1, 1]
    end

    test "nested segments are flattened" do
      assert to_bit_list(<<0b11::2, <<0b10::2, 0b1::1, 0b10::2>>, 0b11::2>>) ==
               [1, 1, 1, 0, 1, 1, 0, 1, 1]
    end
  end

  describe "bitstring value" do
    test "defaults for bitstring value" do
      # 4010 == 0b111110101010
      assert to_bit_list(<<(<<4010::12>>)>>) == [1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0]
    end
  end

  describe "float value" do
    test "defaults for float value" do
      # <<123.45>> == <<64, 94, 220, 204, 204, 204, 204, 205>>
      # 64 == 0b01000000
      # 94 == 0b01011110
      # 220 == 0b11011100
      # 204 == 0b11001100
      # 204 == 0b11001100
      # 204 == 0b11001100
      # 204 == 0b11001100
      # 205 == 0b11001101

      assert to_bit_list(<<123.45>>) == to_bit_list(<<64, 94, 220, 204, 204, 204, 204, 205>>)

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
  end

  describe "integer value" do
    test "defaults for positive integer value that fits in 8 bits" do
      # 170 == 0b10101010
      assert to_bit_list(<<170>>) == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "defaults for negative integer value that fits in 8 bits" do
      # -22 == 0b11101010
      # 234 == 0b11101010
      assert to_bit_list(<<-22>>) == to_bit_list(<<234>>)
      assert to_bit_list(<<-22>>) == [1, 1, 1, 0, 1, 0, 1, 0]
    end

    test "defaults for positive integer value that fits in 12 bits" do
      # 4010 == 0b111110101010
      # 170 == 0b10101010
      assert to_bit_list(<<4010>>) == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "defaults for negative integer value that fits in 12 bits" do
      # -86 == 0b111110101010
      # 170 == 0b10101010
      assert to_bit_list(<<-86>>) == to_bit_list(<<170>>)
      assert to_bit_list(<<-86>>) == [1, 0, 1, 0, 1, 0, 1, 0]
    end
  end

  describe "string value" do
    test "defaults for string value" do
      # <<"全息图">> == <<229, 133, 168, 230, 129, 175, 229, 155, 190>>
      # 229 == 0b11100101
      # 133 == 0b10000101
      # 168 == 0b10101000
      # 230 == 0b11100110
      # 129 == 0b10000001
      # 175 == 0b10101111
      # 229 == 0b11100101
      # 155 == 0b10011011
      # 190 == 0b10111110

      assert to_bit_list(<<"全息图">>) ==
               to_bit_list(<<229, 133, 168, 230, 129, 175, 229, 155, 190>>)

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          1, 1, 1, 0, 0, 1, 0, 1,
          1, 0, 0, 0, 0, 1, 0, 1,
          1, 0, 1, 0, 1, 0, 0, 0,
          1, 1, 1, 0, 0, 1, 1, 0,
          1, 0, 0, 0, 0, 0, 0, 1,
          1, 0, 1, 0, 1, 1, 1, 1,
          1, 1, 1, 0, 0, 1, 0, 1,
          1, 0, 0, 1, 1, 0, 1, 1,
          1, 0, 1, 1, 1, 1, 1, 0
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(<<"全息图">>) == bits
    end
  end

  describe "values of not supported data types" do
    defp build_bitstring(term) do
      (fn segment -> <<segment>> end).(term)
    end

    test "atom values are not supported" do
      assert_raise ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: :abc",
                   fn -> build_bitstring(:abc) end
    end

    test "list values are not supported" do
      assert_raise ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: [1, 2]",
                   fn -> build_bitstring([1, 2]) end
    end

    test "tuple values are not supported" do
      assert_raise ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: {1, 2}",
                   fn -> build_bitstring({1, 2}) end
    end

    # TODO: anonymous function, map, pid, port, reference
  end
end
