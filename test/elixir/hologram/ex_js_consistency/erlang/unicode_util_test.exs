defmodule Hologram.ExJsConsistency.Erlang.UnicodeUtilTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/unicode_util_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "cp/1" do
    # Section: with binary input

    test "returns empty list for empty binary" do
      assert :unicode_util.cp("") == []
    end

    test "extracts first codepoint from single character" do
      assert :unicode_util.cp("a") == [97 | ""]
    end

    test "extracts first codepoint from multi-character string" do
      assert :unicode_util.cp("hello") == [104 | "ello"]
    end

    test "handles UTF-8 character (German ß)" do
      assert :unicode_util.cp("ßtest") == [223 | "test"]
    end

    test "handles emoji (outside BMP)" do
      assert :unicode_util.cp("😀test") == [128_512 | "test"]
    end

    test "returns error tuple for invalid UTF-8" do
      invalid_binary = <<255, 255>>

      assert :unicode_util.cp(invalid_binary) == {:error, invalid_binary}
    end

    test "returns error tuple for surrogate pair" do
      # Create invalid UTF-8 with surrogate pair codepoint
      invalid_binary = <<0xED, 0xA0, 0x80>>

      assert :unicode_util.cp(invalid_binary) == {:error, invalid_binary}
    end

    # Section: with list of integers

    test "returns empty list for empty list" do
      assert :unicode_util.cp([]) == []
    end

    test "extracts single integer" do
      assert :unicode_util.cp([97]) == [97]
    end

    test "extracts first integer from list" do
      assert :unicode_util.cp([104, 101, 108]) == [104, 101, 108]
    end

    test "handles zero codepoint" do
      assert :unicode_util.cp([0]) == [0]
    end

    test "handles maximum valid codepoint" do
      assert :unicode_util.cp([0x10FFFF]) == [0x10FFFF]
    end

    test "does not validate surrogate pair codepoint in list" do
      # Erlang does not validate surrogate pairs in integer lists
      assert :unicode_util.cp([55_296]) == [55_296]
    end

    test "raises FunctionClauseError for negative integer" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [-1])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp([-1])
      end
    end

    test "raises FunctionClauseError for integer above maximum" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [0x110000])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp([0x110000])
      end
    end

    # Section: with list starting with binary

    test "extracts codepoint from single character binary" do
      assert :unicode_util.cp(["a", 98]) == [97, "", 98]
    end

    test "extracts codepoint from multi-character binary" do
      assert :unicode_util.cp(["hello", 97]) == [104, "ello", 97]
    end

    test "handles binary alone in list" do
      assert :unicode_util.cp(["test"]) == [116 | "est"]
    end

    test "skips empty binary and processes next element" do
      assert :unicode_util.cp(["", 97]) == [97]
    end

    test "handles multiple empty binaries" do
      assert :unicode_util.cp(["", "", 97]) == [97]
    end

    test "returns error tuple for invalid UTF-8 in binary" do
      invalid_binary = <<255, 255>>

      assert :unicode_util.cp([invalid_binary]) == {:error, invalid_binary}
    end

    test "raises FunctionClauseError for non-byte-aligned bitstring" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [<<1::1, 0::1, 1::1>>])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp([<<1::1, 0::1, 1::1>>])
      end
    end

    # Section: with nested list

    test "extracts from single nested integer" do
      assert :unicode_util.cp([[97]]) == [97]
    end

    test "extracts from nested list with multiple integers" do
      assert :unicode_util.cp([[104, 101], 108]) == [104, 101, 108]
    end

    test "extracts from nested list with binary" do
      assert :unicode_util.cp([["ab"], 99]) == [97, "b", 99]
    end

    test "skips empty nested list" do
      assert :unicode_util.cp([[], 97]) == [97]
    end

    test "handles deeply nested list" do
      assert :unicode_util.cp([[[97]]]) == [97]
    end

    test "returns empty list for nested empty lists" do
      assert :unicode_util.cp([[], []]) == []
    end

    # Section: with improper lists

    test "handles improper list with integer tail" do
      assert :unicode_util.cp([97 | 98]) == [97 | 98]
    end

    test "handles improper list with binary tail" do
      assert :unicode_util.cp([97 | "bc"]) == [97 | "bc"]
    end

    test "handles improper list with binary head and tail" do
      assert :unicode_util.cp(["ab" | "cd"]) == [97, "b" | "cd"]
    end

    test "handles improper list with binary and empty list tail" do
      assert :unicode_util.cp(["ab" | []]) == [97 | "b"]
    end

    test "handles improper list with empty binary and empty list tail" do
      assert :unicode_util.cp(["" | []]) == []
    end

    test "handles improper list with empty lists" do
      assert :unicode_util.cp([[] | []]) == []
    end

    test "passes through improper list with atom tail" do
      assert :unicode_util.cp([97 | :atom]) == [97 | :atom]
    end

    test "passes through improper list with float tail" do
      assert :unicode_util.cp([97 | 3.14]) == [97 | 3.14]
    end

    test "passes through improper list with non-byte-aligned bitstring tail" do
      bitstring = <<1::1, 0::1, 1::1>>

      assert :unicode_util.cp([97 | bitstring]) == [97 | bitstring]
    end

    test "passes through improper list with invalid UTF-8 binary tail" do
      invalid_binary = <<255, 255>>

      assert :unicode_util.cp([97 | invalid_binary]) == [97 | invalid_binary]
    end

    test "handles nested improper list with integers" do
      assert :unicode_util.cp([[97 | 98]]) == [97 | 98]
    end

    test "passes through nested improper list with atom tail" do
      assert :unicode_util.cp([[97 | :atom]]) == [97 | :atom]
    end

    test "handles nested improper list with binary and empty list tail" do
      assert :unicode_util.cp([["ab" | []]]) == [97 | "b"]
    end

    test "handles improper list with nested valid codepoint and binary tail" do
      assert :unicode_util.cp([[97, 98] | <<"cd">>]) == [97, 98 | <<"cd">>]
    end

    test "raises FunctionClauseError for nested improper list with empty list and integer tail" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [97])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp([[[] | 97]])
      end
    end

    test "raises FunctionClauseError for nested improper list with empty binary and integer tail" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [97])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp([["" | 97]])
      end
    end

    # Section: with mixed content

    test "handles multiple binaries in list" do
      assert :unicode_util.cp(["ab", "cd", 97]) == [97, "b", "cd", 97]
    end

    test "handles consecutive non-empty binaries in list" do
      assert :unicode_util.cp([<<"ab">>, <<"cd">>, <<"ef">>]) ==
               [97, "b", <<"cd">>, <<"ef">>]
    end

    test "handles list with alternating integers and binaries" do
      assert :unicode_util.cp([97, <<"b">>, 99, <<"d">>]) ==
               [97, "b", 99, "d"]
    end

    test "does not error on invalid UTF-8 after valid integer" do
      invalid_binary = <<255, 255>>

      assert :unicode_util.cp([97, invalid_binary]) == [97, invalid_binary]
    end

    test "handles very long list of integers" do
      long_list = Enum.to_list(1..100)
      result = :unicode_util.cp(long_list)

      assert result == long_list
      assert length(result) == 100
    end

    test "handles nested then flat integers" do
      assert :unicode_util.cp([[97, 98], 99, 100]) == [97, 98, 99, 100]
    end

    test "handles very deeply nested lists" do
      assert :unicode_util.cp([[[[97]]]]) == [97]
    end

    test "handles multiple nested empty binaries with following integer" do
      assert :unicode_util.cp([[""], [""], 97]) == [97]
    end

    test "handles nested empty binary and empty list with following integer" do
      assert :unicode_util.cp([["", []], 97]) == [97]
    end

    test "handles empty nested list followed by valid nested list" do
      assert :unicode_util.cp([[], [97]]) == [97]
    end

    test "handles list with only empty nested lists" do
      assert :unicode_util.cp([[], [], []]) == []
    end

    # Section: UTF-8 and encoding edge cases

    test "handles codepoint at 0 (null character)" do
      assert :unicode_util.cp([0]) == [0]
    end

    test "handles binary containing null character" do
      assert :unicode_util.cp(<<0, 97, 98>>) == [0 | <<97, 98>>]
    end

    test "handles BMP boundary - maximum BMP codepoint" do
      assert :unicode_util.cp([0xFFFF]) == [0xFFFF]
    end

    test "handles first codepoint above BMP" do
      assert :unicode_util.cp([0x10000]) == [0x10000]
    end

    test "handles UTF-8 two-byte character (¢)" do
      # ¢ is codepoint 162 (0xA2), encoded as 0xC2 0xA2 in UTF-8
      assert :unicode_util.cp(<<0xC2, 0xA2, 99>>) == [162 | <<99>>]
    end

    test "handles UTF-8 three-byte character (€)" do
      # € is codepoint 8364, encoded as 0xE2 0x82 0xAC in UTF-8
      assert :unicode_util.cp(<<0xE2, 0x82, 0xAC>>) == [8364 | ""]
    end

    test "returns error tuple for overlong UTF-8 encoding" do
      invalid_binary = <<0xC0, 0x80>>

      assert :unicode_util.cp(invalid_binary) == {:error, invalid_binary}
    end

    test "returns error tuple for lone continuation byte" do
      invalid_binary = <<0x80>>

      assert :unicode_util.cp(invalid_binary) == {:error, invalid_binary}
    end

    test "returns error tuple for invalid 5-byte UTF-8 sequence" do
      invalid_binary = <<0xF8, 0x80, 0x80, 0x80, 0x80>>

      assert :unicode_util.cp(invalid_binary) == {:error, invalid_binary}
    end

    test "returns error tuple for truncated UTF-8 sequence" do
      invalid_binary = <<0xC3>>

      assert :unicode_util.cp(invalid_binary) == {:error, invalid_binary}
    end

    test "returns error tuple for nested invalid UTF-8" do
      invalid_binary = <<255, 255>>

      assert :unicode_util.cp([[invalid_binary]]) == {:error, invalid_binary}
    end

    # Section: error handling

    test "raises FunctionClauseError for integer input" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [42])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp(42)
      end
    end

    test "raises FunctionClauseError for atom input" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [:test])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp(:test)
      end
    end

    test "raises FunctionClauseError for float input" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [3.14])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp(3.14)
      end
    end

    test "raises FunctionClauseError for non-byte-aligned bitstring (direct)" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [<<1::1, 0::1, 1::1>>])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp(<<1::1, 0::1, 1::1>>)
      end
    end

    test "raises FunctionClauseError for list with atom" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [:invalid])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp([:invalid])
      end
    end

    test "raises FunctionClauseError for list with atom head and tail" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cpl/2", [:a, [:b]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp([:a, :b])
      end
    end

    test "raises FunctionClauseError for list with float" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [3.14])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp([3.14])
      end
    end
  end

  describe "gc/1" do
    # Section: with binary input

    test "returns empty list for empty binary" do
      assert :unicode_util.gc("") == []
    end

    test "extracts first grapheme from ascii string" do
      assert :unicode_util.gc("ab") == [97 | "b"]
    end

    test "handles grapheme with combining mark" do
      assert :unicode_util.gc("e̊x") == [[101, 778] | "x"]
    end

    test "returns error tuple for invalid UTF-8" do
      invalid_binary = <<255, 255>>

      assert :unicode_util.gc(invalid_binary) == {:error, invalid_binary}
    end

    # Section: with list input

    test "returns empty list for empty list" do
      assert :unicode_util.gc([]) == []
    end

    test "extracts single-codepoint cluster when next codepoint is non-combining" do
      assert :unicode_util.gc([97, 98]) == [97, 98]
    end

    test "groups combining marks across integers" do
      assert :unicode_util.gc([97, 778, 120]) == [[97, 778], 120]
    end

    test "handles list starting with binary" do
      assert :unicode_util.gc(["ab", 98]) == [97, "b", 98]
    end

    test "handles binary with combining marks inside list" do
      assert :unicode_util.gc(["e̊", 120]) == [[101, 778], "", 120]
    end

    test "handles integer followed by empty binary" do
      assert :unicode_util.gc([97, <<>>]) == [97, <<>>]
    end

    # Section: error handling

    test "raises FunctionClauseError for non-byte-aligned bitstring" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [<<1::1, 0::1, 1::1>>])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.gc(<<1::1, 0::1, 1::1>>)
      end
    end

    test "raises FunctionClauseError for integer input" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [42])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.gc(42)
      end
    end
  end
end
