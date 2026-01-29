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

  describe "characters_to_nfd_binary/1" do
    test "decomposes combining characters to NFD" do
      assert :unicode.characters_to_nfd_binary("å") == "a\u030a"
    end

    test "handles already decomposed text" do
      # "a\u030a" is already in NFD form
      input = "a\u030a"

      assert :unicode.characters_to_nfd_binary(input) == input
    end

    test "decomposes nested chardata" do
      input = [<<"abc..">>, [<<"a">>, 0x030A], <<"a">>, [0x0308], <<"o">>, 0x0308]

      assert :unicode.characters_to_nfd_binary(input) == "abc..a\u030aa\u0308o\u0308"
    end

    test "handles empty binary" do
      assert :unicode.characters_to_nfd_binary("") == ""
    end

    test "handles empty list" do
      assert :unicode.characters_to_nfd_binary([]) == ""
    end

    test "handles deeply nested lists" do
      input = [[[<<"a">>, 0x030A]]]

      assert :unicode.characters_to_nfd_binary(input) == "a\u030a"
    end

    test "handles multiple combining marks" do
      input = [<<"o">>, 0x0308, 0x0304]

      # NFD preserves combining marks in canonical order
      assert :unicode.characters_to_nfd_binary(input) == "o\u0308\u0304"
    end

    test "handles large input" do
      large_input = String.duplicate("abcdefghij", 100)

      assert :unicode.characters_to_nfd_binary(large_input) == large_input
    end

    test "handles mixed ASCII and Unicode" do
      input = [<<"hello">>, <<"  ">>, <<"å">>, <<"  world">>]

      assert :unicode.characters_to_nfd_binary(input) == "hello  a\u030a  world"
    end

    test "preserves non-combining characters" do
      input = [0x3042, 0x3044]

      assert :unicode.characters_to_nfd_binary(input) == "あい"
    end

    test "returns error tuple on invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>
      input = [<<"abc">>, invalid_binary]
      expected = {:error, <<"abc">>, invalid_binary}

      assert :unicode.characters_to_nfd_binary(input) == expected
    end

    test "rejects overlong UTF-8 sequence in binary" do
      # Overlong encoding of NUL: 0xC0 0x80 (invalid)
      invalid_binary = <<0xC0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfd_binary(input) == expected
    end

    test "rejects UTF-16 surrogate range in binary" do
      # CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      invalid_binary = <<0xED, 0xA0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfd_binary(input) == expected
    end

    test "rejects code points above U+10FFFF in binary" do
      # Leader 0xF5 starts sequences above Unicode max (invalid)
      invalid_binary = <<0xF5, 0x80, 0x80, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfd_binary(input) == expected
    end

    test "returns error tuple for truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = ["a", incomplete_binary]

      expected = {:error, "a", incomplete_binary}

      assert :unicode.characters_to_nfd_binary(input) == expected
    end

    test "raises ArgumentError when input is not a list or a bitstring" do
      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfd_binary(:abc)
      end
    end

    test "raises ArgumentError when input is a non-binary bitstring" do
      input = <<1::1, 0::1, 1::1>>

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfd_binary(input)
      end
    end

    test "raises ArgumentError when input list contains invalid types" do
      input = [123.45, :abc]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfd_binary(input)
      end
    end

    test "raises ArgumentError on invalid code point" do
      input = [97, 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfd_binary(input)
      end
    end

    test "raises ArgumentError on invalid code point after normalization" do
      input = [<<"a">>, 0x030A, 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfd_binary(input)
      end
    end
  end

  describe "characters_to_nfkc_binary/1" do
    test "normalizes combining characters to NFKC" do
      assert :unicode.characters_to_nfkc_binary("a\u030a") == "å"
    end

    test "handles already normalized text" do
      assert :unicode.characters_to_nfkc_binary("åäö") == "åäö"
    end

    test "normalizes nested chardata" do
      input = ["abc..", ["a", 0x030A], "a", [0x0308], "o", 0x0308]

      assert :unicode.characters_to_nfkc_binary(input) == "abc..åäö"
    end

    test "handles empty binary" do
      assert :unicode.characters_to_nfkc_binary("") == ""
    end

    test "handles empty list" do
      assert :unicode.characters_to_nfkc_binary([]) == ""
    end

    test "handles deeply nested lists" do
      input = [[["a", 0x030A]]]

      assert :unicode.characters_to_nfkc_binary(input) == "å"
    end

    test "handles multiple combining marks" do
      input = ["o", 0x0308, 0x0304]

      # Normalized form combines these in canonical order
      assert :unicode.characters_to_nfkc_binary(input) == "ȫ"
    end

    test "handles large input" do
      large_input = String.duplicate("abcdefghij", 100)

      assert :unicode.characters_to_nfkc_binary(large_input) == large_input
    end

    test "handles mixed ASCII and Unicode" do
      input = ["hello", " ", "a", 0x030A, " world"]

      assert :unicode.characters_to_nfkc_binary(input) == "hello å world"
    end

    test "preserves non-combining characters" do
      input = [0x3042, 0x3044]

      assert :unicode.characters_to_nfkc_binary(input) == "あい"
    end

    test "normalizes compatibility characters" do
      # NFKC normalizes compatibility characters like ℌ (U+210C) to H (U+0048)
      input = "\u210C"

      assert :unicode.characters_to_nfkc_binary(input) == "H"
    end

    test "normalizes ligatures" do
      # NFKC normalizes ligatures like ﬁ (U+FB01) to fi (U+0066 U+0069)
      input = "\uFB01"

      assert :unicode.characters_to_nfkc_binary(input) == "fi"
    end

    test "normalizes width variants" do
      # NFKC normalizes fullwidth forms like Ａ (U+FF21) to A (U+0041)
      input = "\uFF21"

      assert :unicode.characters_to_nfkc_binary(input) == "A"
    end

    test "normalizes fullwidth numbers" do
      # NFKC normalizes fullwidth digits: ３２ -> 32
      input = [0xFF13, 0xFF12]

      assert :unicode.characters_to_nfkc_binary(input) == "32"
    end

    test "returns error tuple on invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>
      input = ["abc", invalid_binary]
      expected = {:error, "abc", invalid_binary}

      assert :unicode.characters_to_nfkc_binary(input) == expected
    end

    test "rejects overlong UTF-8 sequence in binary" do
      # Overlong encoding of NUL: 0xC0 0x80 (invalid)
      invalid_binary = <<0xC0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfkc_binary(input) == expected
    end

    test "rejects UTF-16 surrogate range in binary" do
      # CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      invalid_binary = <<0xED, 0xA0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfkc_binary(input) == expected
    end

    test "rejects code points above U+10FFFF in binary" do
      # Leader 0xF5 starts sequences above Unicode max (invalid)
      invalid_binary = <<0xF5, 0x80, 0x80, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfkc_binary(input) == expected
    end

    test "returns error tuple for truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = ["a", incomplete_binary]

      expected = {:error, "a", incomplete_binary}

      assert :unicode.characters_to_nfkc_binary(input) == expected
    end

    test "returns error tuple for single invalid binary not wrapped in a list" do
      invalid_binary = <<255, 255>>

      expected = {:error, "", invalid_binary}

      assert :unicode.characters_to_nfkc_binary(invalid_binary) == expected
    end

    test "raises ArgumentError when input is not a list or a bitstring" do
      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkc_binary(:abc)
      end
    end

    test "raises ArgumentError when input is a non-binary bitstring" do
      input = <<1::1, 0::1, 1::1>>

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkc_binary(input)
      end
    end

    test "raises ArgumentError when input list contains invalid types" do
      input = [123.45, :abc]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkc_binary(input)
      end
    end

    test "raises ArgumentError on negative integer code point" do
      input = [-1]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkc_binary(input)
      end
    end

    test "raises ArgumentError on invalid code point before normalization" do
      input = [97, 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkc_binary(input)
      end
    end

    test "raises ArgumentError on invalid code point after normalization" do
      input = ["a", 0x030A, 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkc_binary(input)
      end
    end
  end

  describe "characters_to_nfkd_binary/1" do
    test "normalizes combining characters to NFKD" do
      # Input: "a" + combining ring above (decomposed form)
      # NFKD: keeps it as decomposed
      assert :unicode.characters_to_nfkd_binary("a\u030a") == "a\u030a"
    end

    test "decomposes already normalized precomposed characters" do
      # Input: precomposed "å" (U+00E5)
      # NFKD: decomposes to "a" + combining ring above (U+0061 + U+030A)
      assert :unicode.characters_to_nfkd_binary("å") == "a\u030a"
    end

    test "normalizes nested chardata" do
      input = [
        "abc..",
        ["a", 0x030A],
        "a",
        [0x0308],
        "o",
        0x0308
      ]

      # Expected: "abc.." + "a\u030a" + "a\u0308" + "o\u0308"
      assert :unicode.characters_to_nfkd_binary(input) == "abc..a\u030aa\u0308o\u0308"
    end

    test "handles empty binary" do
      assert :unicode.characters_to_nfkd_binary("") == ""
    end

    test "handles empty list" do
      assert :unicode.characters_to_nfkd_binary([]) == ""
    end

    test "handles deeply nested lists" do
      input = [
        [
          [
            "a",
            0x030A
          ]
        ]
      ]

      assert :unicode.characters_to_nfkd_binary(input) == "a\u030a"
    end

    test "handles multiple combining marks" do
      input = [
        "o",
        0x0308,
        0x0304
      ]

      # NFKD keeps combining marks as-is
      assert :unicode.characters_to_nfkd_binary(input) == "o\u0308\u0304"
    end

    test "handles large input" do
      large_input = String.duplicate("abcdefghij", 100)
      assert :unicode.characters_to_nfkd_binary(large_input) == large_input
    end

    test "handles mixed ASCII and Unicode" do
      input = [
        "hello",
        " ",
        "a",
        0x030A,
        " world"
      ]

      assert :unicode.characters_to_nfkd_binary(input) == "hello a\u030a world"
    end

    test "preserves non-combining characters" do
      input = [0x3042, 0x3044]
      assert :unicode.characters_to_nfkd_binary(input) == "あい"
    end

    test "normalizes compatibility characters" do
      # NFKD normalizes compatibility characters like ℌ (U+210C) to H (U+0048)
      input = "\u210C"
      assert :unicode.characters_to_nfkd_binary(input) == "H"
    end

    test "normalizes ligatures" do
      # NFKD normalizes ligatures like ﬁ (U+FB01) to fi (U+0066 U+0069)
      input = "\uFB01"
      assert :unicode.characters_to_nfkd_binary(input) == "fi"
    end

    test "normalizes width variants" do
      # NFKD normalizes fullwidth forms like Ａ (U+FF21) to A (U+0041)
      input = "\uFF21"
      assert :unicode.characters_to_nfkd_binary(input) == "A"
    end

    test "returns error tuple on invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>
      input = ["abc", invalid_binary]
      expected = {:error, "abc", invalid_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "normalizes prefix in error tuple" do
      # Prefix contains precomposed "å" (U+00E5) which should be normalized to "a" + U+030A
      invalid_binary = <<255, 255>>
      input = ["å", invalid_binary]
      expected = {:error, "a\u030a", invalid_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects overlong encoding (2-byte for ASCII)" do
      # Overlong encoding: 'A' (U+0041) encoded as 2 bytes: 0xC1 0x81
      invalid_binary = <<0xC1, 0x81>>
      input = ["abc", invalid_binary]
      expected = {:error, "abc", invalid_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects overlong encoding (3-byte for 2-byte range)" do
      # Overlong encoding: U+007F encoded as 3 bytes: 0xE0 0x81 0xBF
      invalid_binary = <<0xE0, 0x81, 0xBF>>
      input = ["test", invalid_binary]
      expected = {:error, "test", invalid_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects UTF-16 surrogate (high surrogate)" do
      # UTF-16 high surrogate: U+D800 encoded as 0xED 0xA0 0x80
      invalid_binary = <<0xED, 0xA0, 0x80>>
      input = ["hello", invalid_binary]
      expected = {:error, "hello", invalid_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects UTF-16 surrogate (low surrogate)" do
      # UTF-16 low surrogate: U+DFFF encoded as 0xED 0xBF 0xBF
      invalid_binary = <<0xED, 0xBF, 0xBF>>
      input = ["world", invalid_binary]
      expected = {:error, "world", invalid_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects code point above U+10FFFF" do
      # U+110000 encoded as 4 bytes: 0xF4 0x90 0x80 0x80
      invalid_binary = <<0xF4, 0x90, 0x80, 0x80>>
      input = ["xyz", invalid_binary]
      expected = {:error, "xyz", invalid_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects 4-byte overlong encoding" do
      # Overlong encoding: U+FFFF encoded as 4 bytes: 0xF0 0x8F 0xBF 0xBF
      invalid_binary = <<0xF0, 0x8F, 0xBF, 0xBF>>
      input = ["pre", invalid_binary]
      expected = {:error, "pre", invalid_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "returns error tuple for truncated UTF-8 sequence" do
      # Truncated UTF-8: start of a 2-byte sequence without continuation
      truncated_binary = <<0xC3>>
      input = ["test", truncated_binary]
      expected = {:error, "test", truncated_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects standalone continuation byte" do
      # Continuation byte (10xxxxxx) at start of sequence is invalid
      invalid_binary = <<0x80>>
      input = ["valid", invalid_binary]
      expected = {:error, "valid", invalid_binary}
      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "raises ArgumentError when input is not a list or a bitstring" do
      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkd_binary(:abc)
      end
    end

    test "raises ArgumentError when input is a single integer" do
      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkd_binary(65)
      end
    end

    test "raises ArgumentError when input is a non-binary bitstring" do
      input = <<1::1, 0::1, 1::1>>

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkd_binary(input)
      end
    end

    test "raises ArgumentError when input list contains invalid types" do
      input = [123.45, :abc]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkd_binary(input)
      end
    end

    test "raises ArgumentError on invalid code point before normalization" do
      input = [97, 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkd_binary(input)
      end
    end

    test "raises ArgumentError on invalid code point after normalization" do
      input = [
        "a",
        0x030A,
        0x110000
      ]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkd_binary(input)
      end
    end
  end
end
