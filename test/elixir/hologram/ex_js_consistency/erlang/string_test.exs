defmodule Hologram.ExJsConsistency.Erlang.StringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/string_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "titlecase/1" do
    # Binary input tests
    test "returns empty binary for empty string" do
      assert :string.titlecase("") == ""
    end

    test "uppercases first character of ASCII string" do
      assert :string.titlecase("hello") == "Hello"
    end

    test "handles already uppercase first character" do
      assert :string.titlecase("Hello") == "Hello"
    end

    test "handles single lowercase character" do
      assert :string.titlecase("a") == "A"
    end

    test "handles single uppercase character" do
      assert :string.titlecase("Z") == "Z"
    end

    test "uses custom mapping for German ß (223 → [83, 115] = 'Ss')" do
      assert :string.titlecase("ßtest") == "Sstest"
    end

    test "uses range check for Georgian character (codepoint 4304)" do
      input = <<4304::utf8, "test">>
      expected = <<4304::utf8, "test">>
      assert :string.titlecase(input) == expected
    end

    test "uses range check for Greek character (codepoint 8072)" do
      input = <<8072::utf8, "test">>
      expected = <<8072::utf8, "test">>
      assert :string.titlecase(input) == expected
    end

    test "uses range check for Greek character (codepoint 8088)" do
      input = <<8088::utf8>>
      expected = <<8088::utf8>>
      assert :string.titlecase(input) == expected
    end

    test "uses range check for Greek character (codepoint 8104)" do
      input = <<8104::utf8>>
      expected = <<8104::utf8>>
      assert :string.titlecase(input) == expected
    end

    test "uses range check for Greek character (codepoint 8111)" do
      input = <<8111::utf8, "end">>
      expected = <<8111::utf8, "end">>
      assert :string.titlecase(input) == expected
    end

    test "uses range check for character (codepoint 68976)" do
      input = <<68_976::utf8>>
      expected = <<68_976::utf8>>
      assert :string.titlecase(input) == expected
    end

    test "uses custom mapping from MAPPING object (452 → 453)" do
      input = <<452::utf8, "test">>
      expected = <<453::utf8, "test">>
      assert :string.titlecase(input) == expected
    end

    test "uses custom mapping for ligature ﬁ (64257 → [70, 105] = 'Fi')" do
      input = <<64_257::utf8, "re">>
      assert :string.titlecase(input) == "Fire"
    end

    test "uses custom mapping that expands to multiple codepoints (8114 → [8122, 837])" do
      input = <<8114::utf8, "x">>
      expected = <<8122::utf8, 837::utf8, "x">>
      assert :string.titlecase(input) == expected
    end

    test "uses custom mapping for ligature ﬃ (64259 → [70, 102, 105] = 'Ffi')" do
      input = <<64_259::utf8>>
      assert :string.titlecase(input) == "Ffi"
    end

    test "uses JavaScript toUpperCase for regular character" do
      assert :string.titlecase("world") == "World"
    end

    test "raises ArgumentError for invalid UTF-8 binary" do
      invalid_binary = <<255, 255>>

      assert_raise ArgumentError, fn ->
        :string.titlecase(invalid_binary)
      end
    end

    test "raises ArgumentError for surrogate pair codepoint" do
      # Create a binary with surrogate pair codepoint (55296)
      invalid_binary = <<0xED, 0xA0, 0x80>>

      assert_raise ArgumentError, fn ->
        :string.titlecase(invalid_binary)
      end
    end

    # List with integer first element tests
    test "returns empty list for empty list" do
      assert :string.titlecase([]) == []
    end

    test "uppercases first codepoint in charlist" do
      assert :string.titlecase([97, 98, 99]) == [65, 98, 99]
    end

    test "handles already uppercase first codepoint" do
      assert :string.titlecase([72, 105]) == [72, 105]
    end

    test "handles single lowercase codepoint" do
      assert :string.titlecase([122]) == [90]
    end

    test "expands first codepoint to multiple codepoints (ß = 223 → [83, 115])" do
      assert :string.titlecase([223, 97]) == [83, 115, 97]
    end

    test "expands first codepoint to three codepoints (64259 → [70, 102, 105])" do
      assert :string.titlecase([64_259, 120]) == [70, 102, 105, 120]
    end

    test "uses range check for codepoint 4304" do
      assert :string.titlecase([4304, 97]) == [4304, 97]
    end

    test "uses custom mapping for codepoint 452" do
      assert :string.titlecase([452, 97]) == [453, 97]
    end

    test "uses custom mapping that expands for codepoint 8114" do
      assert :string.titlecase([8114, 120]) == [8122, 837, 120]
    end

    test "uses JavaScript toUpperCase for regular codepoint" do
      assert :string.titlecase([119]) == [87]
    end

    test "does not validate surrogate pair codepoint in charlist" do
      # Erlang does not validate surrogate pairs in charlists
      assert :string.titlecase([55_296]) == [55_296]
    end

    # List with binary first element tests
    test "processes single character binary" do
      assert :string.titlecase(["a", 98]) == [65, "", 98]
    end

    test "processes multi-character binary" do
      assert :string.titlecase(["hello", 97]) == [72, "ello", 97]
    end

    test "processes binary alone in list" do
      assert :string.titlecase(["test"]) == [84, "est"]
    end

    test "expands binary first char to multiple codepoints (ß)" do
      assert :string.titlecase(["ßx", 97]) == [83, 115, "x", 97]
    end

    test "expands binary first char with ligature ﬁ (64257)" do
      input = [<<64_257::utf8, "le">>]
      assert :string.titlecase(input) == [[70, 105], "le"]
    end

    test "raises ArgumentError for invalid UTF-8 binary in list" do
      invalid_binary = <<255, 255>>

      assert_raise ArgumentError, fn ->
        :string.titlecase([invalid_binary])
      end
    end

    test "returns empty list for empty binary in list" do
      assert :string.titlecase([""]) == []
    end

    # Nested list tests
    test "processes nested list with only integers, rest only integers" do
      assert :string.titlecase([[97], 98]) == [65, 98]
    end

    test "processes nested list with multiple integers, rest with integers" do
      assert :string.titlecase([[104, 101], 108, 108]) == [72, 101, 108, 108]
    end

    test "processes nested list where rest starts with binary" do
      assert :string.titlecase([[97], "test", 99]) == [65, "test", 99]
    end

    test "processes nested list where rest starts with binary, no remainder" do
      assert :string.titlecase([[97], "test"]) == [65, "test"]
    end

    test "processes nested list with binary inside, multiple rest elements" do
      assert :string.titlecase([["ab"], 99, 100]) == [65, "b", 99, 100]
    end

    test "processes nested list with binary inside, single rest element" do
      assert :string.titlecase([["ab"], 99]) == [65, "b", 99]
    end

    test "processes nested list with no rest" do
      assert :string.titlecase([[120]]) == [88]
    end

    test "processes deeply nested list" do
      assert :string.titlecase([[[97]]]) == [65]
    end

    test "processes nested list with binary that expands" do
      assert :string.titlecase([["ß"]]) == [83, 115]
    end

    test "processes nested list with integer that expands" do
      assert :string.titlecase([[223], 97]) == [83, 115, 97]
    end

    test "processes triple nested list" do
      assert :string.titlecase([[[[122]]]]) == [90]
    end

    # Error handling tests
    test "raises FunctionClauseError for integer input" do
      assert_raise FunctionClauseError, fn ->
        :string.titlecase(42)
      end
    end

    test "raises FunctionClauseError for atom input" do
      assert_raise FunctionClauseError, fn ->
        :string.titlecase(:test)
      end
    end

    test "raises FunctionClauseError for float input" do
      assert_raise FunctionClauseError, fn ->
        :string.titlecase(3.14)
      end
    end

    test "raises FunctionClauseError for list with atom first element" do
      assert_raise FunctionClauseError, fn ->
        :string.titlecase([:invalid])
      end
    end

    test "raises FunctionClauseError for list with float first element" do
      assert_raise FunctionClauseError, fn ->
        :string.titlecase([3.14])
      end
    end

    test "raises FunctionClauseError for list with map first element" do
      assert_raise FunctionClauseError, fn ->
        :string.titlecase([%{a: 1}])
      end
    end

    test "raises FunctionClauseError for list with tuple first element" do
      assert_raise FunctionClauseError, fn ->
        :string.titlecase([{1, 2}])
      end
    end
  end
end
