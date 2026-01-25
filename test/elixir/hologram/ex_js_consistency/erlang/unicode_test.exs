defmodule Hologram.ExJsConsistency.Erlang.UnicodeTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/unicode_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.BitstringUtils, only: [to_bit_list: 1]

  @moduletag :consistency

  test "characters_to_binary/1" do
    assert :unicode.characters_to_binary("全息图") ==
             :unicode.characters_to_binary("全息图", :utf8, :utf8)
  end

  describe "characters_to_binary/3" do
    test "input is an empty list" do
      assert :unicode.characters_to_binary([], :utf8, :utf8) == <<>>
    end

    test "input is a list of ASCII code points" do
      input = [?a, ?b, ?c]
      result = :unicode.characters_to_binary(input, :utf8, :utf8)

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

      assert to_bit_list(result) == bits
    end

    test "input is a list of non-ASCII code points (Chinese)" do
      input = [?全, ?息, ?图]
      result = :unicode.characters_to_binary(input, :utf8, :utf8)

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

      assert to_bit_list(result) == bits
    end

    test "input is a binary bitstring" do
      input = <<"abc">>
      assert :unicode.characters_to_binary(input, :utf8, :utf8) == input
    end

    test "input is a non-binary bitstring" do
      input = <<1::1, 0::1, 1::1>>

      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :unicode.characters_to_binary(input, :utf8, :utf8)
                   end
    end

    test "input is a list of binary bitstrings" do
      input = [<<"abc">>, <<"def">>, <<"ghi">>]
      assert :unicode.characters_to_binary(input, :utf8, :utf8) == <<"abcdefghi">>
    end

    test "input is a list of non-binary bitstrings" do
      input = [
        <<1::1, 1::1, 0::1>>,
        <<1::1, 0::1, 1::1>>,
        <<0::1, 1::1, 1::1>>
      ]

      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :unicode.characters_to_binary(input, :utf8, :utf8)
                   end
    end

    test "input is a list of code points mixed with binary bitstrings" do
      input = [
        ?a,
        <<"bcd">>,
        ?e,
        <<"fgh">>,
        ?i
      ]

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == <<"abcdefghi">>
    end

    test "input is a list of elements of types other than a list or a bitstring" do
      input = [123.45, :abc]

      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :unicode.characters_to_binary(input, :utf8, :utf8)
                   end
    end

    test "input is not a list or a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :unicode.characters_to_binary(:abc, :utf8, :utf8)
                   end
    end

    test "input is a nested list" do
      input = [
        ?a,
        [
          ?b,
          [
            ?c,
            <<"def">>,
            ?g
          ],
          ?h
        ],
        ?i
      ]

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == <<"abcdefghi">>
    end

    test "input contains invalid code points" do
      input = [
        ?a,
        <<"bcd">>,
        # Max Unicode code point value is 1,114,112
        1_114_113,
        <<"efg">>
      ]

      expected = {:error, <<"abcd">>, [1_114_113, <<"efg">>]}

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end
  end

  describe "characters_to_list/1" do
    test "UTF8 binary" do
      assert :unicode.characters_to_list("全息图") == [20_840, 24_687, 22_270]
    end

    test "list of UTF8 binaries" do
      assert :unicode.characters_to_list(["abc", "全息图", "xyz"]) == [
               97,
               98,
               99,
               20_840,
               24_687,
               22_270,
               120,
               121,
               122
             ]
    end
  end

  describe "characters_to_nfc_binary/1" do
    test "normalizes combining characters to NFC" do
      assert :unicode.characters_to_nfc_binary("a\u030a") == "å"
    end

    test "handles already normalized text" do
      assert :unicode.characters_to_nfc_binary("åäö") == "åäö"
    end

    test "normalizes nested chardata" do
      input = ["abc..", ["a", 0x030A], "a", [0x0308], "o", 0x0308]

      assert :unicode.characters_to_nfc_binary(input) == "abc..åäö"
    end

    test "handles empty binary" do
      assert :unicode.characters_to_nfc_binary("") == ""
    end

    test "handles empty list" do
      assert :unicode.characters_to_nfc_binary([]) == ""
    end

    test "handles deeply nested lists" do
      input = [[["a", 0x030A]]]

      assert :unicode.characters_to_nfc_binary(input) == "å"
    end

    test "returns error tuple on invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>
      input = ["abc", invalid_binary]
      expected = {:error, "abc", invalid_binary}

      assert :unicode.characters_to_nfc_binary(input) == expected
    end

    test "rejects overlong UTF-8 sequence in binary" do
      # Overlong encoding of NUL: 0xC0 0x80 (invalid)
      invalid_binary = <<0xC0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfc_binary(input) == expected
    end

    test "rejects UTF-16 surrogate range in binary" do
      # CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      invalid_binary = <<0xED, 0xA0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfc_binary(input) == expected
    end

    test "rejects code points above U+10FFFF in binary" do
      # Leader 0xF5 starts sequences above Unicode max (invalid)
      invalid_binary = <<0xF5, 0x80, 0x80, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfc_binary(input) == expected
    end

    test "returns error tuple for truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = ["a", incomplete_binary]

      expected = {:error, "a", incomplete_binary}

      assert :unicode.characters_to_nfc_binary(input) == expected
    end

    test "handles multiple combining marks" do
      input = ["o", 0x0308, 0x0304]

      # Normalized form combines these in canonical order
      assert :unicode.characters_to_nfc_binary(input) == "ȫ"
    end

    test "handles large input" do
      large_input = String.duplicate("abcdefghij", 100)

      assert :unicode.characters_to_nfc_binary(large_input) == large_input
    end

    test "handles mixed ASCII and Unicode" do
      input = ["hello", " ", "a", 0x030A, " world"]

      assert :unicode.characters_to_nfc_binary(input) == "hello å world"
    end

    test "preserves non-combining characters" do
      input = [0x3042, 0x3044]

      assert :unicode.characters_to_nfc_binary(input) == "あい"
    end

    test "raises ArgumentError when input is not a list or a bitstring" do
      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_binary(:abc)
      end
    end

    test "raises ArgumentError when input is a non-binary bitstring" do
      input = <<1::1, 0::1, 1::1>>

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_binary(input)
      end
    end

    test "raises ArgumentError when input list contains invalid types" do
      input = [123.45, :abc]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_binary(input)
      end
    end

    test "raises ArgumentError on invalid code point before normalization" do
      input = [97, 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_binary(input)
      end
    end

    test "raises ArgumentError on invalid code point after normalization" do
      input = ["a", 0x030A, 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_binary(input)
      end
    end
  end
end
