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

    # Section: error handling"

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

    test "raises FunctionClauseError for non-byte-aligned bitstring direct input" do
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

    test "raises FunctionClauseError for list with float" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [3.14])

      assert_error FunctionClauseError, expected_msg, fn ->
        :unicode_util.cp([3.14])
      end
    end
  end
end
