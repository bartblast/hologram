defmodule Hologram.ExJsConsistency.BitstringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/bitstring_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.BitstringUtils, only: [to_bit_list: 1]

  @moduletag :consistency

  # The build_from_value/1 and build_from_value_with_*_*_modifier/1 helpers
  # enable to built bitstrings with specific value and modifier combinations,
  # which wouldn't compile otherwise.

  defp build_from_value(value) do
    <<value>>
  end

  defp build_from_value_with_binary_type_modifier(value) do
    <<value::binary>>
  end

  defp build_from_value_with_bitstring_type_modifier(value) do
    <<value::bitstring>>
  end

  defp build_from_value_with_float_type_modifier(value) do
    <<value::float>>
  end

  defp build_from_value_with_integer_type_modifier(value) do
    <<value::integer>>
  end

  defp build_from_value_with_signed_signedness_modifier(value) do
    <<value::signed>>
  end

  defp build_from_value_with_size_modifier(value, size) do
    <<value::size(size)>>
  end

  defp build_from_value_with_size_and_unit_modifier(value, size) do
    <<value::size(size)-unit(2)>>
  end

  defp build_from_value_with_unsigned_signedness_modifier(value) do
    <<value::signed>>
  end

  defp build_from_value_with_utf8_type_modifier(value) do
    <<value::utf8>>
  end

  defp build_from_value_with_utf16_type_modifier(value) do
    <<value::utf16>>
  end

  defp build_from_value_with_utf32_type_modifier(value) do
    <<value::utf32>>
  end

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

  describe "defaults" do
    test "for bitstring value" do
      assert to_bit_list(<<(<<1::1, 0::1, 1::1, 0::1>>)>>) == [1, 0, 1, 0]
    end

    test "for float value" do
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

    test "for positive integer value that fits in 8 bits" do
      # 170 == 0b10101010
      assert to_bit_list(<<170>>) == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "for negative integer value that fits in 8 bits" do
      # -22 == 0b11101010
      # 234 == 0b11101010

      assert <<-22>> == <<234>>
      assert to_bit_list(<<-22>>) == [1, 1, 1, 0, 1, 0, 1, 0]
    end

    test "for positive integer value that fits in 12 bits" do
      # 4010 == 0b111110101010
      # 170 == 0b10101010

      assert <<4_010>> == <<170>>
      assert to_bit_list(<<4_010>>) == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "for negative integer value that fits in 12 bits" do
      # -86 == 0b111110101010
      # 170 == 0b10101010

      assert <<-86>> == <<170>>
      assert to_bit_list(<<-86>>) == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "for string value" do
      assert <<"全息图">> == <<229, 133, 168, 230, 129, 175, 229, 155, 190>>

      # 229 == 0b11100101
      # 133 == 0b10000101
      # 168 == 0b10101000
      # 230 == 0b11100110
      # 129 == 0b10000001
      # 175 == 0b10101111
      # 229 == 0b11100101
      # 155 == 0b10011011
      # 190 == 0b10111110

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

  describe "binary type modifier" do
    test "with bitstring value when number of bits is divisible by 8" do
      assert to_bit_list(<<(<<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>)::binary>>) ==
               [1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "with bitstring value when number of bits is not divisible by 8" do
      # 5 == 0b101

      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'binary': the size of the value <<5::size(3)>> is not a multiple of the unit for the segment",
                   fn -> build_from_value_with_binary_type_modifier(<<1::1, 0::1, 1::1>>) end
    end

    test "with float value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45",
                   fn -> build_from_value_with_binary_type_modifier(123.45) end
    end

    test "with integer value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 170",
                   fn -> build_from_value_with_binary_type_modifier(170) end
    end

    test "with string value" do
      # See the defaults test for string value.
      assert <<"全息图"::binary>> == <<"全息图">>
    end
  end

  describe "bitstring type modifier" do
    test "with bitstring value" do
      # See the defaults test for bitstring value.
      assert <<(<<1::1, 0::1, 1::1, 0::1>>)::bitstring>> == <<1::1, 0::1, 1::1, 0::1>>
    end

    test "with float value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45",
                   fn -> build_from_value_with_bitstring_type_modifier(123.45) end
    end

    test "with integer value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 170",
                   fn -> build_from_value_with_bitstring_type_modifier(170) end
    end

    test "with string value" do
      # See the defaults test for string value.
      assert <<"全息图"::bitstring>> == <<"全息图">>
    end
  end

  describe "float type modifier" do
    test "with bitstring value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: <<5::size(3)>>",
                   fn -> build_from_value_with_float_type_modifier(<<1::1, 0::1, 1::1>>) end
    end

    test "with float value" do
      # See the defaults test for float value.
      assert <<123.45::float>> == <<123.45>>
    end

    test "with integer value" do
      assert <<1_234_567_890_123_456_789::float>> == <<1_234_567_890_123_456_789.0>>
      assert <<1_234_567_890_123_456_789.0>> == <<67, 177, 34, 16, 244, 125, 233, 129>>

      # 67 == 0b01000011
      # 177 == 0b10110001
      # 34 == 0b00100010
      # 16 == 0b00010000
      # 244 == 0b11110100
      # 125 == 0b01111101
      # 233 == 0b11101001
      # 129 == 0b10000001

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          0, 1, 0, 0, 0, 0, 1, 1,
          1, 0, 1, 1, 0, 0, 0, 1,
          0, 0, 1, 0, 0, 0, 1, 0,
          0, 0, 0, 1, 0, 0, 0, 0,
          1, 1, 1, 1, 0, 1, 0, 0,
          0, 1, 1, 1, 1, 1, 0, 1,
          1, 1, 1, 0, 1, 0, 0, 1,
          1, 0, 0, 0, 0, 0, 0, 1
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(<<1_234_567_890_123_456_789::float>>) == bits
    end

    test "with string value consisting of a single ASCI character" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: \"a\"",
                   fn -> build_from_value_with_float_type_modifier("a") end
    end

    test "with string value consisting of multiple ASCI characters" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: \"abc\"",
                   fn -> build_from_value_with_float_type_modifier("abc") end
    end
  end

  describe "integer type modifier" do
    test "with bitstring value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<5::size(3)>>",
                   fn -> build_from_value_with_integer_type_modifier(<<1::1, 0::1, 1::1>>) end
    end

    test "with float value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45",
                   fn -> build_from_value_with_integer_type_modifier(123.45) end
    end

    test "with integer value" do
      # See the defaults test for integer value.
      assert <<170::integer>> == <<170>>
      assert <<-22::integer>> == <<-22>>
      assert <<4_010::integer>> == <<4_010>>
      assert <<-86::integer>> == <<-86>>
    end

    test "with string value consisting of a single ASCI character" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: \"a\"",
                   fn -> build_from_value_with_integer_type_modifier("a") end
    end

    test "with string value consisting of multiple ASCI characters" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: \"abc\"",
                   fn -> build_from_value_with_integer_type_modifier("abc") end
    end
  end

  describe "signed signedness modifier" do
    test "with bitstring value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<10::size(4)>>",
                   fn ->
                     build_from_value_with_signed_signedness_modifier(<<1::1, 0::1, 1::1, 0::1>>)
                   end
    end

    test "with float value" do
      assert <<123.45::signed>> == <<123.45>>
    end

    test "with integer value" do
      assert <<123::signed>> == <<123>>
    end

    test "with string value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: \"abc\"",
                   fn ->
                     build_from_value_with_signed_signedness_modifier("abc")
                   end
    end
  end

  describe "size modifier" do
    test "with bitstring value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<10::size(4)>>",
                   fn ->
                     build_from_value_with_size_modifier(<<1::1, 0::1, 1::1, 0::1>>, 3)
                   end
    end

    test "with float value when size * unit results in 16, 32 or 64" do
      # Use variable `size` to prevent compilation error in Elixir/OTP versions that don't support size 16.
      size = wrap_term(16)

      assert <<123.45::size(size)>> == <<87, 183>>

      # 87 == 0b01010111
      # 183 == 0b10110111

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          0, 1, 0, 1, 0, 1, 1, 1,
          1, 0, 1, 1, 0, 1, 1, 1
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(<<123.45::size(size)>>) == bits
    end

    test "with float value when size * unit doesn't result in 16, 32 or 64" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45",
                   fn ->
                     build_from_value_with_size_modifier(123.45, 7)
                   end
    end

    test "with integer value" do
      # 183 == 0b10110111
      # 23 == 0b10111
      assert <<183::size(5)>> == <<23::size(5)>>
      assert to_bit_list(<<183::size(5)>>) == [1, 0, 1, 1, 1]
    end

    test "with string value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: \"abc\"",
                   fn ->
                     build_from_value_with_size_modifier("abc", 7)
                   end
    end
  end

  describe "unit modifier (with size modifier)" do
    test "with bitstring value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<170>>",
                   fn ->
                     # 170 == 0b10101010
                     build_from_value_with_size_and_unit_modifier(
                       <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>,
                       3
                     )
                   end
    end

    test "with float value when size * unit results in 16, 32 or 64" do
      # Use variable `size` to prevent compilation error.
      size = wrap_term(8)

      assert <<123.45::size(size)-unit(2)>> == <<87, 183>>

      # 87 == 0b01010111
      # 183 == 0b10110111

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          0, 1, 0, 1, 0, 1, 1, 1,
          1, 0, 1, 1, 0, 1, 1, 1
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(<<123.45::size(size)-unit(2)>>) == bits
    end

    test "with float value when size * unit doesn't result in 16, 32 or 64" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45",
                   fn ->
                     build_from_value_with_size_and_unit_modifier(123.45, 7)
                   end
    end

    test "with integer value" do
      # 170 == 0b10101010
      # 42 == 0b101010
      assert <<170::size(3)-unit(2)>> == <<42::size(6)>>
      assert to_bit_list(<<170::size(3)-unit(2)>>) == [1, 0, 1, 0, 1, 0]
    end

    test "with string value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: \"abc\"",
                   fn ->
                     build_from_value_with_size_and_unit_modifier("abc", 7)
                   end
    end
  end

  describe "unsigned signedness modifier" do
    test "with bitstring value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<10::size(4)>>",
                   fn ->
                     build_from_value_with_unsigned_signedness_modifier(
                       <<1::1, 0::1, 1::1, 0::1>>
                     )
                   end
    end

    test "with float value" do
      assert <<123.45::unsigned>> == <<123.45>>
    end

    test "with integer value" do
      assert <<123::unsigned>> == <<123>>
    end

    test "with string value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: \"abc\"",
                   fn ->
                     build_from_value_with_unsigned_signedness_modifier("abc")
                   end
    end
  end

  describe "utf8 type modifier" do
    test "with bitstring value" do
      assert <<"a">> == <<0::1, 1::1, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1>>

      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: \"a\"",
                   fn ->
                     build_from_value_with_utf8_type_modifier(
                       <<0::1, 1::1, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1>>
                     )
                   end
    end

    test "with float value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: 123.45",
                   fn -> build_from_value_with_utf8_type_modifier(123.45) end
    end

    test "with integer value that is a valid Unicode code point" do
      # ?全 == 20_840
      assert <<20_840::utf8>> == <<"全"::utf8>>
      assert <<20_840::utf8>> == <<229, 133, 168>>

      # 229 == 0b11100101
      # 133 == 0b10000101
      # 168 == 0b10101000

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          1, 1, 1, 0, 0, 1, 0, 1,
          1, 0, 0, 0, 0, 1, 0, 1,
          1, 0, 1, 0, 1, 0, 0, 0
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(<<20_840::utf8>>) == bits
    end

    test "with integer value that is not a valid Unicode code point" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: 1114113",
                   fn -> build_from_value_with_utf8_type_modifier(1_114_113) end
    end

    test "with literal string value" do
      # See the defaults test for string value.
      assert <<"全息图"::utf8>> == <<"全息图">>
    end

    test "with runtime string value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: \"abc\"",
                   fn -> build_from_value_with_utf8_type_modifier("abc") end
    end
  end

  describe "utf16 type modifier" do
    test "with bitstring value" do
      assert <<"a">> == <<0::1, 1::1, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1>>

      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: \"a\"",
                   fn ->
                     build_from_value_with_utf16_type_modifier(
                       <<0::1, 1::1, 1::1, 0::1, 0::1, 0::1, 0::1, 1::1>>
                     )
                   end
    end

    test "with integer value that is a valid Unicode code point" do
      # ?全 == 20_840
      assert <<20_840::utf16>> == <<"全"::utf16>>
      assert <<20_840::utf16>> == <<81, 104>>

      # 81 == 0b01010001
      # 104 == 0b01101000

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          0, 1, 0, 1, 0, 0, 0, 1,
          0, 1, 1, 0, 1, 0, 0, 0
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(<<20_840::utf16>>) == bits
    end

    test "with integer value that is not a valid Unicode code point" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: 1114113",
                   fn -> build_from_value_with_utf16_type_modifier(1_114_113) end
    end

    test "with literal string value" do
      assert <<"全息图"::utf16>> == <<81, 104, 96, 111, 86, 254>>

      # 81 == 0b01010001
      # 104 == 0b01101000
      # 96 == 0b01100000
      # 111 == 0b01101111
      # 86 == 0b01010110
      # 254 == 0b11111110

      # Specified this way, because it's not possible to make the formatter ignore specific lines of code.
      bits =
        """
        [
          0, 1, 0, 1, 0, 0, 0, 1,
          0, 1, 1, 0, 1, 0, 0, 0,
          0, 1, 1, 0, 0, 0, 0, 0,
          0, 1, 1, 0, 1, 1, 1, 1,
          0, 1, 0, 1, 0, 1, 1, 0,
          1, 1, 1, 1, 1, 1, 1, 0
        ]
        """
        |> Code.eval_string()
        |> elem(0)

      assert to_bit_list(<<"全息图"::utf16>>) == bits
    end

    test "with runtime string value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: \"abc\"",
                   fn -> build_from_value_with_utf16_type_modifier("abc") end
    end
  end

  describe "utf32 type modifier" do
    test "with runtime string value" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'utf32': expected a non-negative integer encodable as utf32 but got: \"abc\"",
                   fn -> build_from_value_with_utf32_type_modifier("abc") end
    end
  end

  describe "values of not supported data types" do
    test "atom values are not supported" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: :abc",
                   fn ->
                     build_from_value(:abc)
                   end
    end

    test "list values are not supported" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: [1, 2]",
                   fn ->
                     build_from_value([1, 2])
                   end
    end

    test "tuple values are not supported" do
      assert_error ArgumentError,
                   "construction of binary failed: segment 1 of type 'integer': expected an integer but got: {1, 2}",
                   fn ->
                     build_from_value({1, 2})
                   end
    end

    # TODO: anonymous function, map, pid, port, reference
  end

  describe "with empty string segments" do
    test "the last segment is an empty string" do
      assert <<1, "">> == <<1>>
    end

    test "the first segment is an empty string" do
      assert <<"", 1>> == <<1>>
    end

    test "the middle segment is an empty string" do
      assert <<1, "", 2>> == <<1, 2>>
    end
  end

  # Other bitstring modifier combinations that can't be tested:
  #
  # iex> var = "abc"
  # iex> <<var::utf8-size(3)>>
  # size and unit are not supported on utf types (CompileError)
  #
  # iex> var = "abc"
  # iex> <<var::utf8-unit(3)>>
  # size and unit are not supported on utf types (CompileError)
end
