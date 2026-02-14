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

    test "handles large input" do
      str = String.duplicate("abcdefghij", 100)
      large_input = str

      assert :unicode.characters_to_binary(large_input, :utf8, :utf8) == str
    end

    test "handles mixed ASCII and Unicode" do
      input = ["hello", " ", 0x3042, " world"]

      expected = <<"hello ", 0x3042::utf8, " world">>

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end

    test "returns error tuple on invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>
      input = ["abc", invalid_binary]
      expected = {:error, <<"abc">>, [invalid_binary]}

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end

    test "rejects overlong UTF-8 sequence in binary" do
      # Overlong encoding of NUL: 0xC0 0x80 (invalid)
      invalid_binary = <<0xC0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, <<"a">>, [invalid_binary]}

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end

    test "rejects UTF-16 surrogate range in binary" do
      # CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      invalid_binary = <<0xED, 0xA0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, <<"a">>, [invalid_binary]}

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end

    test "rejects code points above U+10FFFF in binary" do
      # Leader 0xF5 starts sequences above Unicode max (invalid)
      invalid_binary = <<0xF5, 0x80, 0x80, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, <<"a">>, [invalid_binary]}

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end

    test "returns incomplete tuple for truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = ["a", incomplete_binary]

      expected = {:incomplete, <<"a">>, incomplete_binary}

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end

    test "returns error tuple for single invalid binary not wrapped in a list" do
      invalid_binary = <<255, 255>>
      expected = {:error, <<>>, invalid_binary}

      assert :unicode.characters_to_binary(invalid_binary, :utf8, :utf8) == expected
    end

    test "returns incomplete tuple for single truncated binary not wrapped in a list" do
      # First byte of a 2-byte sequence (incomplete)
      incomplete_binary = <<0xC3>>

      expected = {:incomplete, <<>>, incomplete_binary}

      assert :unicode.characters_to_binary(incomplete_binary, :utf8, :utf8) == expected
    end

    test "returns error tuple when invalid UTF-8 appears after valid prefix in binary" do
      invalid_binary = <<"A", 0xC3, 0x28>>

      expected = {:error, "A", <<0xC3, 0x28>>}

      assert :unicode.characters_to_binary(invalid_binary, :utf8, :utf8) == expected
    end

    test "returns incomplete tuple when truncated UTF-8 appears after valid prefix in binary" do
      incomplete_binary = <<"A", 0xC3>>

      expected = {:incomplete, "A", <<0xC3>>}

      assert :unicode.characters_to_binary(incomplete_binary, :utf8, :utf8) == expected
    end

    test "returns error tuple when invalid UTF-8 appears after valid prefix in list" do
      invalid_binary = <<"B", 0xC3, 0x28>>
      input = ["A", invalid_binary]

      expected = {:error, "AB", [<<0xC3, 0x28>>]}

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end

    test "returns incomplete tuple when truncated UTF-8 appears after valid prefix in list" do
      incomplete_binary = <<"B", 0xC3>>
      input = ["A", incomplete_binary]

      expected = {:incomplete, "AB", <<0xC3>>}

      assert :unicode.characters_to_binary(input, :utf8, :utf8) == expected
    end

    test "converts UTF-8 input to latin1 output" do
      assert :unicode.characters_to_binary("Å", :utf8, :latin1) == <<0xC5>>
    end

    test "converts latin1 input to UTF-8 output" do
      assert :unicode.characters_to_binary(<<0xC5>>, :latin1, :utf8) == "Å"
    end

    test "rejects out-of-range codepoints when encoding to latin1 from binary" do
      # U+0100 (Ā) is beyond latin1 range
      assert :unicode.characters_to_binary("Ā", :utf8, :latin1) == {:error, "", "Ā"}
    end

    test "rejects out-of-range codepoints when encoding to latin1 from integer list" do
      assert :unicode.characters_to_binary([256], :utf8, :latin1) == {:error, "", [[256]]}
    end

    test "encodes valid prefix when encountering out-of-range codepoint for latin1" do
      assert :unicode.characters_to_binary([65, 66, 256], :utf8, :latin1) ==
               {:error, "AB", [[256]]}
    end

    test "converts UTF-8 input to UTF-16 output" do
      assert :unicode.characters_to_binary("A", :utf8, {:utf16, :big}) == <<0x00, 0x41>>
      assert :unicode.characters_to_binary("A", :utf8, {:utf16, :little}) == <<0x41, 0x00>>
    end

    test "converts UTF-8 input to UTF-32 output" do
      assert :unicode.characters_to_binary("A", :utf8, {:utf32, :big}) ==
               <<0x00, 0x00, 0x00, 0x41>>

      assert :unicode.characters_to_binary("A", :utf8, {:utf32, :little}) ==
               <<0x41, 0x00, 0x00, 0x00>>
    end

    test "bare :utf16 atom defaults to big-endian" do
      assert :unicode.characters_to_binary("A", :utf8, :utf16) ==
               <<0x00, 0x41>>
    end

    test "bare :utf32 atom defaults to big-endian" do
      assert :unicode.characters_to_binary("A", :utf8, :utf32) ==
               <<0x00, 0x00, 0x00, 0x41>>
    end

    test "explicit little-endian tuples match only little-endian" do
      # UTF-16: little-endian differs from big-endian
      assert :unicode.characters_to_binary("A", :utf8, {:utf16, :little}) ==
               <<0x41, 0x00>>

      assert :unicode.characters_to_binary("A", :utf8, {:utf16, :big}) ==
               <<0x00, 0x41>>

      assert :unicode.characters_to_binary("A", :utf8, {:utf16, :little}) !=
               :unicode.characters_to_binary("A", :utf8, {:utf16, :big})

      # UTF-32: little-endian differs from big-endian
      assert :unicode.characters_to_binary("A", :utf8, {:utf32, :little}) ==
               <<0x41, 0x00, 0x00, 0x00>>

      assert :unicode.characters_to_binary("A", :utf8, {:utf32, :big}) ==
               <<0x00, 0x00, 0x00, 0x41>>

      assert :unicode.characters_to_binary("A", :utf8, {:utf32, :little}) !=
               :unicode.characters_to_binary("A", :utf8, {:utf32, :big})
    end

    # Input encoding tests
    test "converts UTF-16 BE input to UTF-8 output" do
      assert :unicode.characters_to_binary(<<0x00, 0x41>>, {:utf16, :big}, :utf8) == "A"
    end

    test "converts UTF-16 LE input to UTF-8 output" do
      assert :unicode.characters_to_binary(<<0x41, 0x00>>, {:utf16, :little}, :utf8) == "A"
    end

    test "converts UTF-32 BE input to UTF-8 output" do
      assert :unicode.characters_to_binary(<<0x00, 0x00, 0x00, 0x41>>, {:utf32, :big}, :utf8) ==
               "A"
    end

    test "converts UTF-32 LE input to UTF-8 output" do
      assert :unicode.characters_to_binary(<<0x41, 0x00, 0x00, 0x00>>, {:utf32, :little}, :utf8) ==
               "A"
    end

    test "bare :utf16 input defaults to big-endian" do
      assert :unicode.characters_to_binary(<<0x00, 0x41>>, :utf16, :utf8) == "A"
    end

    test "bare :utf32 input defaults to big-endian" do
      assert :unicode.characters_to_binary(<<0x00, 0x00, 0x00, 0x41>>, :utf32, :utf8) == "A"
    end

    test "converts UTF-16 BE multi-byte character to UTF-8" do
      # U+4E2D (中) in UTF-16 BE
      assert :unicode.characters_to_binary(<<0x4E, 0x2D>>, {:utf16, :big}, :utf8) == "中"
    end

    test "converts UTF-16 BE surrogate pair to UTF-8" do
      # U+1F600 (😀) in UTF-16 BE: high surrogate 0xD83D, low surrogate 0xDE00
      assert :unicode.characters_to_binary(
               <<0xD8, 0x3D, 0xDE, 0x00>>,
               {:utf16, :big},
               :utf8
             ) == "😀"
    end

    test "converts UTF-16 LE surrogate pair to UTF-8" do
      # U+1F600 (😀) in UTF-16 LE
      assert :unicode.characters_to_binary(
               <<0x3D, 0xD8, 0x00, 0xDE>>,
               {:utf16, :little},
               :utf8
             ) == "😀"
    end

    test "returns incomplete for truncated UTF-16 BE sequence (1 byte)" do
      assert :unicode.characters_to_binary(<<0x00>>, {:utf16, :big}, :utf8) ==
               {:incomplete, "", <<0x00>>}
    end

    test "returns incomplete for truncated UTF-16 BE sequence after valid prefix" do
      assert :unicode.characters_to_binary(<<0x00, 0x41, 0x00>>, {:utf16, :big}, :utf8) ==
               {:incomplete, "A", <<0x00>>}
    end

    test "returns incomplete for truncated UTF-16 BE surrogate pair (3 bytes)" do
      # High surrogate 0xD83D + partial low surrogate
      assert :unicode.characters_to_binary(
               <<0xD8, 0x3D, 0xDE>>,
               {:utf16, :big},
               :utf8
             ) == {:incomplete, "", <<0xD8, 0x3D, 0xDE>>}
    end

    test "returns error for invalid UTF-16 BE high surrogate alone" do
      # High surrogate without low surrogate (followed by regular char)
      assert :unicode.characters_to_binary(
               <<0xD8, 0x00, 0x00, 0x41>>,
               {:utf16, :big},
               :utf8
             ) == {:error, "", <<0xD8, 0x00, 0x00, 0x41>>}
    end

    test "returns incomplete for invalid UTF-16 BE high surrogate after valid prefix" do
      assert :unicode.characters_to_binary(
               <<0x00, 0x41, 0xD8, 0x00>>,
               {:utf16, :big},
               :utf8
             ) == {:incomplete, "A", <<0xD8, 0x00>>}
    end

    test "returns error for invalid UTF-16 BE low surrogate alone" do
      # Low surrogate without high surrogate
      assert :unicode.characters_to_binary(<<0xDC, 0x00>>, {:utf16, :big}, :utf8) ==
               {:error, "", <<0xDC, 0x00>>}
    end

    test "returns incomplete for truncated UTF-32 BE sequence (3 bytes)" do
      assert :unicode.characters_to_binary(
               <<0x00, 0x00, 0x00>>,
               {:utf32, :big},
               :utf8
             ) == {:incomplete, "", <<0x00, 0x00, 0x00>>}
    end

    test "returns incomplete for truncated UTF-32 BE sequence after valid prefix" do
      assert :unicode.characters_to_binary(
               <<0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00>>,
               {:utf32, :big},
               :utf8
             ) == {:incomplete, "A", <<0x00, 0x00, 0x00>>}
    end

    test "returns error for invalid UTF-32 BE codepoint beyond U+10FFFF" do
      # U+110000 (beyond valid Unicode range)
      assert :unicode.characters_to_binary(
               <<0x00, 0x11, 0x00, 0x00>>,
               {:utf32, :big},
               :utf8
             ) == {:error, "", <<0x00, 0x11, 0x00, 0x00>>}
    end

    test "returns error for invalid UTF-32 BE codepoint after valid prefix" do
      assert :unicode.characters_to_binary(
               <<0x00, 0x00, 0x00, 0x41, 0x00, 0x11, 0x00, 0x00>>,
               {:utf32, :big},
               :utf8
             ) == {:error, "A", <<0x00, 0x11, 0x00, 0x00>>}
    end

    test "returns error for UTF-32 BE surrogate range codepoint" do
      # U+D800 (surrogate range, invalid in UTF-32)
      assert :unicode.characters_to_binary(
               <<0x00, 0x00, 0xD8, 0x00>>,
               {:utf32, :big},
               :utf8
             ) == {:error, "", <<0x00, 0x00, 0xD8, 0x00>>}
    end

    test "converts multiple UTF-16 BE characters to UTF-8" do
      # "AB" in UTF-16 BE
      assert :unicode.characters_to_binary(
               <<0x00, 0x41, 0x00, 0x42>>,
               {:utf16, :big},
               :utf8
             ) == "AB"
    end

    test "converts UTF-16 BE input to latin1 output" do
      # "A" in UTF-16 BE to latin1
      assert :unicode.characters_to_binary(<<0x00, 0x41>>, {:utf16, :big}, :latin1) == "A"
    end

    test "converts UTF-32 LE input to UTF-16 BE output" do
      # "A" from UTF-32 LE to UTF-16 BE
      assert :unicode.characters_to_binary(
               <<0x41, 0x00, 0x00, 0x00>>,
               {:utf32, :little},
               {:utf16, :big}
             ) == <<0x00, 0x41>>
    end

    # Comprehensive input/output encoding combinations
    test "converts latin1 input to latin1 output (identity)" do
      # Å in latin1 - when input and output are both latin1, returns raw bytes
      assert :unicode.characters_to_binary(<<0xC5>>, :latin1, :latin1) == <<0xC5>>
    end

    test "converts UTF-8 input to UTF-8 output (identity)" do
      assert :unicode.characters_to_binary("Å", :utf8, :utf8) == "Å"
    end

    test "converts latin1 input to UTF-8 output (all latin1 range)" do
      # Test with latin1-only characters (0xA0-0xFF range)
      assert :unicode.characters_to_binary(
               <<0xA0, 0xC5, 0xFF>>,
               :latin1,
               :utf8
             ) == <<0xC2, 0xA0, 0xC3, 0x85, 0xC3, 0xBF>>
    end

    test "converts latin1 input to UTF-16 BE output" do
      # latin1 Å (0xC5) → UTF-16 BE (U+00C5)
      assert :unicode.characters_to_binary(<<0xC5>>, :latin1, {:utf16, :big}) ==
               <<0x00, 0xC5>>
    end

    test "converts latin1 input to UTF-16 LE output" do
      # latin1 Å (0xC5) → UTF-16 LE (U+00C5)
      assert :unicode.characters_to_binary(<<0xC5>>, :latin1, {:utf16, :little}) ==
               <<0xC5, 0x00>>
    end

    test "converts latin1 input to UTF-32 BE output" do
      # latin1 Å (0xC5) → UTF-32 BE (U+00C5)
      assert :unicode.characters_to_binary(<<0xC5>>, :latin1, {:utf32, :big}) ==
               <<0x00, 0x00, 0x00, 0xC5>>
    end

    test "converts latin1 input to UTF-32 LE output" do
      # latin1 Å (0xC5) → UTF-32 LE (U+00C5)
      assert :unicode.characters_to_binary(<<0xC5>>, :latin1, {:utf32, :little}) ==
               <<0xC5, 0x00, 0x00, 0x00>>
    end

    test "converts UTF-16 BE input to UTF-16 LE output" do
      # U+4E2D (中) in UTF-16 BE → UTF-16 LE
      assert :unicode.characters_to_binary(<<0x4E, 0x2D>>, {:utf16, :big}, {:utf16, :little}) ==
               <<0x2D, 0x4E>>
    end

    test "converts UTF-16 BE input to UTF-32 BE output" do
      # U+4E2D (中) in UTF-16 BE → UTF-32 BE
      assert :unicode.characters_to_binary(<<0x4E, 0x2D>>, {:utf16, :big}, {:utf32, :big}) ==
               <<0x00, 0x00, 0x4E, 0x2D>>
    end

    test "converts UTF-16 BE input to UTF-32 LE output" do
      # U+4E2D (中) in UTF-16 BE → UTF-32 LE
      assert :unicode.characters_to_binary(<<0x4E, 0x2D>>, {:utf16, :big}, {:utf32, :little}) ==
               <<0x2D, 0x4E, 0x00, 0x00>>
    end

    test "converts UTF-16 BE input to latin1 output (ASCII subset)" do
      # U+0041 (A) in UTF-16 BE → latin1
      assert :unicode.characters_to_binary(<<0x00, 0x41>>, {:utf16, :big}, :latin1) == "A"
    end

    test "converts UTF-16 LE input to latin1 output (ASCII subset)" do
      # U+0041 (A) in UTF-16 LE → latin1
      assert :unicode.characters_to_binary(<<0x41, 0x00>>, {:utf16, :little}, :latin1) == "A"
    end

    test "converts UTF-16 LE input to UTF-16 BE output" do
      # U+4E2D (中) in UTF-16 LE → UTF-16 BE
      assert :unicode.characters_to_binary(<<0x2D, 0x4E>>, {:utf16, :little}, {:utf16, :big}) ==
               <<0x4E, 0x2D>>
    end

    test "converts UTF-16 LE input to UTF-32 BE output" do
      # U+4E2D (中) in UTF-16 LE → UTF-32 BE
      assert :unicode.characters_to_binary(<<0x2D, 0x4E>>, {:utf16, :little}, {:utf32, :big}) ==
               <<0x00, 0x00, 0x4E, 0x2D>>
    end

    test "converts UTF-16 LE input to UTF-32 LE output" do
      # U+4E2D (中) in UTF-16 LE → UTF-32 LE
      assert :unicode.characters_to_binary(
               <<0x2D, 0x4E>>,
               {:utf16, :little},
               {:utf32, :little}
             ) == <<0x2D, 0x4E, 0x00, 0x00>>
    end

    test "converts UTF-32 BE input to UTF-16 BE output" do
      # U+4E2D (中) in UTF-32 BE → UTF-16 BE
      assert :unicode.characters_to_binary(
               <<0x00, 0x00, 0x4E, 0x2D>>,
               {:utf32, :big},
               {:utf16, :big}
             ) == <<0x4E, 0x2D>>
    end

    test "converts UTF-32 BE input to UTF-16 LE output" do
      # U+4E2D (中) in UTF-32 BE → UTF-16 LE
      assert :unicode.characters_to_binary(
               <<0x00, 0x00, 0x4E, 0x2D>>,
               {:utf32, :big},
               {:utf16, :little}
             ) == <<0x2D, 0x4E>>
    end

    test "converts UTF-32 BE input to UTF-32 LE output" do
      # U+4E2D (中) in UTF-32 BE → UTF-32 LE
      assert :unicode.characters_to_binary(
               <<0x00, 0x00, 0x4E, 0x2D>>,
               {:utf32, :big},
               {:utf32, :little}
             ) == <<0x2D, 0x4E, 0x00, 0x00>>
    end

    test "converts UTF-32 BE input to latin1 output (ASCII subset)" do
      # U+0041 (A) in UTF-32 BE → latin1
      assert :unicode.characters_to_binary(
               <<0x00, 0x00, 0x00, 0x41>>,
               {:utf32, :big},
               :latin1
             ) == "A"
    end

    test "converts UTF-32 LE input to UTF-16 LE output" do
      # U+4E2D (中) in UTF-32 LE → UTF-16 LE
      assert :unicode.characters_to_binary(
               <<0x2D, 0x4E, 0x00, 0x00>>,
               {:utf32, :little},
               {:utf16, :little}
             ) == <<0x2D, 0x4E>>
    end

    test "converts UTF-32 LE input to UTF-32 BE output" do
      # U+4E2D (中) in UTF-32 LE → UTF-32 BE
      assert :unicode.characters_to_binary(
               <<0x2D, 0x4E, 0x00, 0x00>>,
               {:utf32, :little},
               {:utf32, :big}
             ) == <<0x00, 0x00, 0x4E, 0x2D>>
    end

    test "converts UTF-32 LE input to latin1 output (ASCII subset)" do
      # U+0041 (A) in UTF-32 LE → latin1
      assert :unicode.characters_to_binary(
               <<0x41, 0x00, 0x00, 0x00>>,
               {:utf32, :little},
               :latin1
             ) == "A"
    end

    test "treats :unicode input encoding like :utf8" do
      assert :unicode.characters_to_binary(<<"A", 0xFF>>, :unicode, :utf8) ==
               {:error, "A", <<0xFF>>}
    end

    test "treats :unicode output encoding like :utf8" do
      assert :unicode.characters_to_binary("A", :utf8, :unicode) == "A"
    end

    test "treats :unicode input and output like :utf8" do
      assert :unicode.characters_to_binary("A", :unicode, :unicode) == "A"
    end

    test "encodes latin1 integer list to UTF-8 when output is utf8" do
      assert :unicode.characters_to_binary([255], :latin1, :utf8) == "ÿ"
    end

    test "encodes latin1 integer list to latin1 when output is latin1" do
      assert :unicode.characters_to_binary([255], :latin1, :latin1) == <<255>>
    end

    test "returns error tuple for UTF-16 surrogate codepoint in list" do
      assert :unicode.characters_to_binary([0xD800], :utf8, :utf8) ==
               {:error, "", [0xD800]}
    end

    test "rejects UTF-32 codepoint with high byte >= 0x80 (above U+10FFFF)" do
      # Invalid UTF-32: 0x80000000 is above Unicode maximum U+10FFFF
      # Big-endian representation of 0x80000000
      invalid_utf32 = <<0x80, 0x00, 0x00, 0x00>>

      result = :unicode.characters_to_binary(invalid_utf32, {:utf32, :big}, :utf8)

      assert result == {:error, "", <<0x80, 0x00, 0x00, 0x00>>}
    end

    test "encodes emoji (supplementary plane) to UTF-16 big-endian with surrogate pairs" do
      # U+1F600 (😀) requires surrogate pair in UTF-16
      emoji = "😀"

      result = :unicode.characters_to_binary(emoji, :utf8, {:utf16, :big})

      # High surrogate: 0xD83D, Low surrogate: 0xDE00
      assert result == <<0xD8, 0x3D, 0xDE, 0x00>>
    end

    test "encodes emoji (supplementary plane) to UTF-16 little-endian with surrogate pairs" do
      # U+1F600 (😀) requires surrogate pair in UTF-16
      emoji = "😀"

      result = :unicode.characters_to_binary(emoji, :utf8, {:utf16, :little})

      # Little-endian: low byte first for each 16-bit unit
      # High surrogate: 0xD83D -> 0x3D, 0xD8
      # Low surrogate: 0xDE00 -> 0x00, 0xDE
      assert result == <<0x3D, 0xD8, 0x00, 0xDE>>
    end

    test "encodes multiple emoji characters to UTF-16 big-endian" do
      # Two emoji: 😀 (U+1F600) and 🎉 (U+1F389)
      emojis = "😀🎉"

      result = :unicode.characters_to_binary(emojis, :utf8, {:utf16, :big})

      # 😀: 0xD83D 0xDE00
      # 🎉: 0xD83C 0xDF89
      assert result == <<0xD8, 0x3D, 0xDE, 0x00, 0xD8, 0x3C, 0xDF, 0x89>>
    end

    test "encodes BMP character mixed with emoji to UTF-16 big-endian" do
      # 'A' (U+0041) is BMP, 😀 (U+1F600) is supplementary
      mixed = "A😀"

      result = :unicode.characters_to_binary(mixed, :utf8, {:utf16, :big})

      # A: 0x0041 (2 bytes)
      # 😀: 0xD83D 0xDE00 (4 bytes)
      assert result == <<0x00, 0x41, 0xD8, 0x3D, 0xDE, 0x00>>
    end
  end

  describe "bom_to_encoding/1" do
    test "detects UTF-8 BOM" do
      assert :unicode.bom_to_encoding(<<0xEF, 0xBB, 0xBF, 0x41>>) == {:utf8, 3}
    end

    test "detects UTF-16 BOMs" do
      assert :unicode.bom_to_encoding(<<0xFE, 0xFF, 0x00, 0x41>>) == {{:utf16, :big}, 2}
      assert :unicode.bom_to_encoding(<<0xFF, 0xFE, 0x41, 0x00>>) == {{:utf16, :little}, 2}
    end

    test "detects UTF-32 BOMs" do
      assert :unicode.bom_to_encoding(<<0x00, 0x00, 0xFE, 0xFF, 0x00>>) == {{:utf32, :big}, 4}
      assert :unicode.bom_to_encoding(<<0xFF, 0xFE, 0x00, 0x00, 0x00>>) == {{:utf32, :little}, 4}
    end

    test "defaults to latin1 without BOM" do
      assert :unicode.bom_to_encoding(<<0x41>>) == {:latin1, 0}
    end
  end

  describe "characters_to_list/1" do
    test "converts binary to list of codepoints" do
      assert :unicode.characters_to_list("abc") == [?a, ?b, ?c]
    end

    test "converts binary with non-ASCII characters (Chinese)" do
      assert :unicode.characters_to_list("全息图") == [?全, ?息, ?图]
    end

    test "converts list of codepoints to list of codepoints" do
      input = [?a, ?b, ?c]

      assert :unicode.characters_to_list(input) == input
    end

    test "converts list of binaries" do
      input = ["abc", "def", "ghi"]

      assert :unicode.characters_to_list(input) == [?a, ?b, ?c, ?d, ?e, ?f, ?g, ?h, ?i]
    end

    test "converts mixed list of codepoints and binaries" do
      input = [?a, "bcd", ?e, "fgh", ?i]

      assert :unicode.characters_to_list(input) == [?a, ?b, ?c, ?d, ?e, ?f, ?g, ?h, ?i]
    end

    test "handles nested lists" do
      input = [
        ?a,
        [
          ?b,
          [
            ?c,
            "def",
            ?g
          ],
          ?h
        ],
        ?i
      ]

      assert :unicode.characters_to_list(input) == [?a, ?b, ?c, ?d, ?e, ?f, ?g, ?h, ?i]
    end

    test "handles empty binary" do
      assert :unicode.characters_to_list(<<>>) == []
    end

    test "handles empty list" do
      assert :unicode.characters_to_list([]) == []
    end

    test "handles deeply nested lists" do
      input = [[["abc"]]]

      assert :unicode.characters_to_list(input) == [?a, ?b, ?c]
    end

    test "handles large input" do
      str = String.duplicate("abcdefghij", 100)
      large_input = str

      assert :unicode.characters_to_list(large_input) == String.to_charlist(str)
    end

    test "handles mixed ASCII and Unicode" do
      input = ["hello", " ", 0x3042, " world"]

      assert :unicode.characters_to_list(input) == [
               ?h,
               ?e,
               ?l,
               ?l,
               ?o,
               ?\s,
               0x3042,
               ?\s,
               ?w,
               ?o,
               ?r,
               ?l,
               ?d
             ]
    end

    test "returns error tuple on invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>
      input = ["abc", invalid_binary]
      expected = {:error, ~c"abc", [invalid_binary]}

      assert :unicode.characters_to_list(input) == expected
    end

    test "rejects overlong UTF-8 sequence in binary" do
      # Overlong encoding of NUL: 0xC0 0x80 (invalid)
      invalid_binary = <<0xC0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, ~c"a", [invalid_binary]}

      assert :unicode.characters_to_list(input) == expected
    end

    test "rejects UTF-16 surrogate range in binary" do
      # CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      invalid_binary = <<0xED, 0xA0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, ~c"a", [invalid_binary]}

      assert :unicode.characters_to_list(input) == expected
    end

    test "rejects code points above U+10FFFF in binary" do
      # Leader 0xF5 starts sequences above Unicode max (invalid)
      invalid_binary = <<0xF5, 0x80, 0x80, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, ~c"a", [invalid_binary]}

      assert :unicode.characters_to_list(input) == expected
    end

    test "returns incomplete tuple for truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = ["a", incomplete_binary]

      expected = {:incomplete, ~c"a", incomplete_binary}

      assert :unicode.characters_to_list(input) == expected
    end

    test "returns error tuple for single invalid binary not wrapped in a list" do
      invalid_binary = <<255, 255>>
      expected = {:error, [], invalid_binary}

      assert :unicode.characters_to_list(invalid_binary) == expected
    end

    test "returns incomplete tuple for single truncated binary not wrapped in a list" do
      # First byte of a 2-byte sequence (incomplete)
      incomplete_binary = <<0xC3>>

      expected = {:incomplete, [], incomplete_binary}

      assert :unicode.characters_to_list(incomplete_binary) == expected
    end

    test "raises ArgumentError when input is not a list or a bitstring" do
      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_list(:abc)
      end
    end

    test "raises ArgumentError when input is a non-binary bitstring" do
      input = <<1::1, 0::1, 1::1>>

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_list(input)
      end
    end

    test "raises ArgumentError when input list contains invalid types" do
      input = [123.45, :abc]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_list(input)
      end
    end

    test "returns error tuple on invalid code point (above max)" do
      input = [97, 0x110000]
      expected = {:error, ~c"a", [0x110000]}

      assert :unicode.characters_to_list(input) == expected
    end

    test "returns error tuple on negative integer code point" do
      input = [-1]
      expected = {:error, [], [-1]}

      assert :unicode.characters_to_list(input) == expected
    end
  end

  # NFC_BINARY: Reference implementation with comprehensive test coverage
  # Tests: composition behavior, structural handling, input validation, error handling, UTF-8 validation
  # This suite serves as the baseline for all other normalization functions
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

    test "rejects invalid UTF-8 in binary" do
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

    test "rejects truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = ["a", incomplete_binary]

      expected = {:error, "a", incomplete_binary}

      assert :unicode.characters_to_nfc_binary(input) == expected
    end

    test "rejects single invalid binary not wrapped in a list" do
      invalid_binary = <<255, 255>>
      result = :unicode.characters_to_nfc_binary(invalid_binary)

      expected = {:error, "", invalid_binary}

      assert result == expected
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

    test "raises ArgumentError on negative integer code point" do
      input = [-1]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_binary(input)
      end
    end
  end

  # NFC_LIST: Output format variation of NFC
  # Tests: same structural and normalization behaviors as NFC_BINARY, but returning a list instead of binary
  describe "characters_to_nfc_list/1" do
    test "normalizes combining characters to NFC" do
      assert :unicode.characters_to_nfc_list([?a, 0x030A]) == [229]
    end

    test "handles already normalized text" do
      assert :unicode.characters_to_nfc_list([229]) == [229]
    end

    test "normalizes nested chardata" do
      input = [<<"abc..a">>, 0x030A, [?a], 0x0308, "o", 0x0308]

      assert :unicode.characters_to_nfc_list(input) == [?a, ?b, ?c, ?., ?., 229, 228, 246]
    end

    test "handles empty binary" do
      assert :unicode.characters_to_nfc_list(<<>>) == []
    end

    test "handles empty list" do
      assert :unicode.characters_to_nfc_list([]) == []
    end

    test "handles deeply nested lists" do
      input = [[[?a, 0x030A]]]

      assert :unicode.characters_to_nfc_list(input) == [229]
    end

    test "handles multiple combining marks" do
      input = [?o, 0x0308, 0x0304]

      # Normalized form combines these in canonical order
      assert :unicode.characters_to_nfc_list(input) == [0x022B]
    end

    test "handles large input" do
      str = String.duplicate("abcdefghij", 100)
      large_input = String.to_charlist(str)

      assert :unicode.characters_to_nfc_list(large_input) == large_input
    end

    test "handles mixed ASCII and Unicode" do
      input = ["hello", " ", [?a, 0x030A], " world"]

      assert :unicode.characters_to_nfc_list(input) == [
               ?h,
               ?e,
               ?l,
               ?l,
               ?o,
               ?\s,
               229,
               ?\s,
               ?w,
               ?o,
               ?r,
               ?l,
               ?d
             ]
    end

    test "preserves non-combining characters" do
      input = [0x3042, 0x3044]

      assert :unicode.characters_to_nfc_list(input) == [0x3042, 0x3044]
    end

    test "rejects invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>
      input = [<<"abc">>, invalid_binary]
      expected = {:error, ~c"abc", invalid_binary}

      assert :unicode.characters_to_nfc_list(input) == expected
    end

    test "rejects overlong UTF-8 sequence in binary" do
      # Overlong encoding of NUL: 0xC0 0x80 (invalid)
      invalid_binary = <<0xC0, 0x80>>

      input = [<<"a">>, invalid_binary]

      expected = {:error, ~c"a", invalid_binary}

      assert :unicode.characters_to_nfc_list(input) == expected
    end

    test "rejects UTF-16 surrogate range in binary" do
      # CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      invalid_binary = <<0xED, 0xA0, 0x80>>

      input = [<<"a">>, invalid_binary]

      expected = {:error, ~c"a", invalid_binary}

      assert :unicode.characters_to_nfc_list(input) == expected
    end

    test "rejects code points above U+10FFFF in binary" do
      # Leader 0xF5 starts sequences above Unicode max (invalid)
      invalid_binary = <<0xF5, 0x80, 0x80, 0x80>>

      input = [<<"a">>, invalid_binary]

      expected = {:error, ~c"a", invalid_binary}

      assert :unicode.characters_to_nfc_list(input) == expected
    end

    test "rejects truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = [<<"a">>, incomplete_binary]

      expected = {:error, ~c"a", incomplete_binary}

      assert :unicode.characters_to_nfc_list(input) == expected
    end

    test "rejects single invalid binary not wrapped in a list" do
      invalid_binary = <<255, 255>>
      expected = {:error, [], invalid_binary}

      assert :unicode.characters_to_nfc_list(invalid_binary) == expected
    end

    test "raises ArgumentError when input is not a list or a bitstring" do
      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_list(:abc)
      end
    end

    test "raises ArgumentError when input is a non-binary bitstring" do
      input = <<1::1, 0::1, 1::1>>

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_list(input)
      end
    end

    test "raises ArgumentError when input list contains invalid types" do
      input = [123.45, :abc]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_list(input)
      end
    end

    test "raises ArgumentError on invalid code point before normalization" do
      input = [97, 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_list(input)
      end
    end

    test "raises ArgumentError on invalid code point after normalization" do
      input = [[?a, 0x030A], 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_list(input)
      end
    end

    test "raises ArgumentError on negative integer code point" do
      input = [-1]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfc_list(input)
      end
    end
  end

  # NFD_BINARY: Decomposition form
  # Tests: only behaviors unique to NFD (decomposition, decomposed preservation, error tuple prefix decomposition)
  # Structural and error handling coverage inherited from NFC_BINARY
  # Canonical decomposition form
  describe "characters_to_nfd_binary/1" do
    # === NFD-SPECIFIC TESTS ===
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

    test "handles multiple combining marks" do
      input = [<<"o">>, 0x0308, 0x0304]

      # NFD preserves combining marks in canonical order
      assert :unicode.characters_to_nfd_binary(input) == "o\u0308\u0304"
    end

    test "normalizes prefix in error tuple" do
      # Prefix contains precomposed "å" (U+00E5) which should be normalized to "a" + U+030A
      invalid_binary = <<255, 255>>

      input = ["å", invalid_binary]

      expected = {:error, "a\u030a", invalid_binary}

      assert :unicode.characters_to_nfd_binary(input) == expected
    end

    # === COMMON STRUCTURAL TESTS ===
    # Inherited from NFC_BINARY

    test "handles empty binary" do
      assert :unicode.characters_to_nfd_binary("") == ""
    end

    test "handles empty list" do
      assert :unicode.characters_to_nfd_binary([]) == ""
    end

    test "handles deeply nested lists" do
      input = [[["å"]]]

      assert :unicode.characters_to_nfd_binary(input) == "a\u030a"
    end

    test "handles large input" do
      large_input = String.duplicate("abcdefghij", 100)

      assert :unicode.characters_to_nfd_binary(large_input) == large_input
    end

    test "handles mixed ASCII and Unicode" do
      input = ["hello", " ", "å", " world"]

      assert :unicode.characters_to_nfd_binary(input) == "hello a\u030a world"
    end

    test "preserves non-combining characters" do
      input = [0x3042, 0x3044]

      assert :unicode.characters_to_nfd_binary(input) == "あい"
    end

    # === COMMON UTF-8 VALIDATION TESTS ===
    # Inherited from NFC_BINARY

    test "rejects invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>
      input = ["abc", invalid_binary]
      expected = {:error, "abc", invalid_binary}

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

    test "rejects truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = ["a", incomplete_binary]

      expected = {:error, "a", incomplete_binary}

      assert :unicode.characters_to_nfd_binary(input) == expected
    end

    test "rejects single invalid binary not wrapped in a list" do
      invalid_binary = <<255, 255>>
      result = :unicode.characters_to_nfd_binary(invalid_binary)

      expected = {:error, "", invalid_binary}

      assert result == expected
    end

    # === COMMON ERROR HANDLING TESTS ===
    # Inherited from NFC_BINARY

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

    test "raises ArgumentError on invalid code point before normalization" do
      input = [97, 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfd_binary(input)
      end
    end

    test "raises ArgumentError on invalid code point after normalization" do
      input = ["å", 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfd_binary(input)
      end
    end

    test "raises ArgumentError on negative integer code point" do
      input = [-1]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfd_binary(input)
      end
    end
  end

  # NFKC_BINARY: Composed form with compatibility transformations
  # Tests: composition (like NFC) + compatibility character/ligature/width normalization
  # Structural and error handling coverage inherited from NFC_BINARY
  # Compatibility composition form
  describe "characters_to_nfkc_binary/1" do
    # === NFKC-SPECIFIC TESTS ===
    test "normalizes combining characters to NFKC (composition)" do
      # NFKC performs composition like NFC
      assert :unicode.characters_to_nfkc_binary("a\u030a") == "å"
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

    # === COMMON STRUCTURAL TESTS ===
    # Inherited from NFC_BINARY

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

    # === COMMON UTF-8 VALIDATION TESTS ===
    # Inherited from NFC_BINARY

    test "rejects invalid UTF-8 in binary" do
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

    test "rejects truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = ["a", incomplete_binary]

      expected = {:error, "a", incomplete_binary}

      assert :unicode.characters_to_nfkc_binary(input) == expected
    end

    test "rejects single invalid binary not wrapped in a list" do
      invalid_binary = <<255, 255>>
      result = :unicode.characters_to_nfkc_binary(invalid_binary)

      expected = {:error, "", invalid_binary}

      assert result == expected
    end

    # === COMMON ERROR HANDLING TESTS ===
    # Inherited from NFC_BINARY

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

    test "raises ArgumentError on negative integer code point" do
      input = [-1]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkc_binary(input)
      end
    end
  end

  # NFKD_BINARY: Decomposed form with compatibility transformations
  # Tests: one canonical decomposition test + compatibility character/ligature/width transformations
  # Full canonical decomposition coverage (nested chardata, error tuple prefix) tested in NFD_BINARY
  # Structural and error handling coverage inherited from NFC_BINARY
  # Compatibility decomposition form
  describe "characters_to_nfkd_binary/1" do
    # === NFKD-SPECIFIC TESTS ===
    test "decomposes already normalized precomposed characters" do
      # Input: precomposed "å" (U+00E5)
      # NFKD: decomposes to "a" + combining ring above (U+0061 + U+030A)
      assert :unicode.characters_to_nfkd_binary("å") == "a\u030a"
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

    # === COMMON STRUCTURAL TESTS ===
    # Inherited from NFC_BINARY

    test "handles already decomposed text" do
      # "a\u030a" is already in NFD form
      input = "a\u030a"

      assert :unicode.characters_to_nfkd_binary(input) == input
    end

    test "decomposes nested chardata" do
      input = [<<"abc..">>, [<<"a">>, 0x030A], <<"a">>, [0x0308], <<"o">>, 0x0308]

      assert :unicode.characters_to_nfkd_binary(input) == "abc..a\u030aa\u0308o\u0308"
    end

    test "handles empty binary" do
      assert :unicode.characters_to_nfkd_binary("") == ""
    end

    test "handles empty list" do
      assert :unicode.characters_to_nfkd_binary([]) == ""
    end

    test "handles deeply nested lists" do
      input = [[["å"]]]

      assert :unicode.characters_to_nfkd_binary(input) == "a\u030a"
    end

    test "handles multiple combining marks" do
      input = [<<"o">>, 0x0308, 0x0304]

      # NFKD preserves combining marks in canonical order
      assert :unicode.characters_to_nfkd_binary(input) == "o\u0308\u0304"
    end

    test "handles large input" do
      large_input = String.duplicate("abcdefghij", 100)

      assert :unicode.characters_to_nfkd_binary(large_input) == large_input
    end

    test "handles mixed ASCII and Unicode" do
      input = ["hello", " ", "å", " world"]

      assert :unicode.characters_to_nfkd_binary(input) == "hello a\u030a world"
    end

    test "preserves non-combining characters" do
      input = [0x3042, 0x3044]

      assert :unicode.characters_to_nfkd_binary(input) == "あい"
    end

    test "normalizes prefix in error tuple" do
      # Prefix contains precomposed "å" (U+00E5) which should be normalized to "a" + U+030A
      invalid_binary = <<255, 255>>

      input = ["å", invalid_binary]

      expected = {:error, "a\u030a", invalid_binary}

      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    # === COMMON UTF-8 VALIDATION TESTS ===
    # Inherited from NFC_BINARY

    test "rejects invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>
      input = ["abc", invalid_binary]
      expected = {:error, "abc", invalid_binary}

      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects overlong UTF-8 sequence in binary" do
      # Overlong encoding of NUL: 0xC0 0x80 (invalid)
      invalid_binary = <<0xC0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects UTF-16 surrogate range in binary" do
      # CESU-8 style encoding of U+D800: 0xED 0xA0 0x80 (invalid in UTF-8)
      invalid_binary = <<0xED, 0xA0, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects code points above U+10FFFF in binary" do
      # Leader 0xF5 starts sequences above Unicode max (invalid)
      invalid_binary = <<0xF5, 0x80, 0x80, 0x80>>

      input = ["a", invalid_binary]

      expected = {:error, "a", invalid_binary}

      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects truncated UTF-8 sequence" do
      # First two bytes of a 3-byte sequence (incomplete)
      incomplete_binary = <<0xE4, 0xB8>>

      input = ["a", incomplete_binary]

      expected = {:error, "a", incomplete_binary}

      assert :unicode.characters_to_nfkd_binary(input) == expected
    end

    test "rejects single invalid binary not wrapped in a list" do
      invalid_binary = <<255, 255>>
      result = :unicode.characters_to_nfkd_binary(invalid_binary)

      expected = {:error, "", invalid_binary}

      assert result == expected
    end

    # === COMMON ERROR HANDLING TESTS ===
    # Inherited from NFC_BINARY

    test "raises ArgumentError when input is not a list or a bitstring" do
      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkd_binary(:abc)
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
      input = ["å", 0x110000]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkd_binary(input)
      end
    end

    test "raises ArgumentError on negative integer code point" do
      input = [-1]

      expected_msg =
        build_argument_error_msg(1, "not valid character data (an iodata term)")

      assert_error ArgumentError, expected_msg, fn ->
        :unicode.characters_to_nfkd_binary(input)
      end
    end
  end
end
