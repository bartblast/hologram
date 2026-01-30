defmodule Hologram.ExJsConsistency.Erlang.StringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/string_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "join/2" do
    test "single element" do
      assert :string.join([~c"hello"], ~c", ") == ~c"hello"
    end

    test "multiple elements" do
      assert :string.join([~c"one", ~c"two", ~c"three"], ~c", ") == ~c"one, two, three"
    end

    test "no elements" do
      assert :string.join([], ~c", ") == []
    end

    test "single-character separator" do
      assert :string.join([~c"apple", ~c"banana", ~c"cherry"], ~c",") ==
               ~c"apple,banana,cherry"
    end

    test "multi-character separator" do
      assert :string.join([~c"apple", ~c"banana", ~c"cherry"], ~c" and ") ==
               ~c"apple and banana and cherry"
    end

    test "empty separator" do
      assert :string.join([~c"hello", ~c"world"], ~c"") == ~c"helloworld"
    end

    test "empty charlists in list" do
      assert :string.join([~c"", ~c"hello", ~c"", ~c"world", ~c""], ~c"-") == ~c"-hello--world-"
    end

    test "lists with non-integer elements" do
      assert :string.join([[:a, :b], [:c, :d]], ~c"abc") == [:a, :b, 97, 98, 99, :c, :d]
    end

    test "raises FunctionClauseError if the first argument is not a list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":string.join/2", [:not_a_list, ~c", "]),
                   fn ->
                     :string.join(:not_a_list, ~c", ")
                   end
    end

    test "raises ErlangError if the first argument is an improper list" do
      list = [~c"hello" | :tail]

      assert_error ErlangError, "Erlang error: {:bad_generator, :tail}", fn ->
        :string.join(list, ~c", ")
      end
    end

    test "raises FunctionClauseError for empty list with non-list separator" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":string.join/2", [[], :not_a_list]),
                   fn ->
                     :string.join([], :not_a_list)
                   end
    end

    test "raises ArgumentError for multiple elements with non-list separator" do
      assert_error ArgumentError, "argument error", fn ->
        :string.join([~c"hello", ~c"world"], :not_a_list)
      end
    end
  end

  describe "replace/3" do
    test "delegates to replace/4 with :leading direction" do
      # Use a string with multiple occurrences of the pattern to verify :leading (not :all or :trailing)
      result = :string.replace("a-b-c", "-", "_")

      assert result == ["a", "_", "b-c"]
      assert result == :string.replace("a-b-c", "-", "_", :leading)
    end
  end

  describe "replace/4" do
    # Direction variations

    test "with direction :all" do
      result = :string.replace("Hello World !", " ", "_", :all)

      assert result == ["Hello", "_", "World", "_", "!"]
    end

    test "with direction :leading" do
      result = :string.replace("Hello World !", " ", "_", :leading)

      assert result == ["Hello", "_", "World !"]
    end

    test "with direction :trailing" do
      result = :string.replace("Hello World !", " ", "_", :trailing)

      assert result == ["Hello World", "_", "!"]
    end

    # Pattern position edge cases

    test "when pattern is at the start of the string" do
      result = :string.replace("Hello", "He", "A", :leading)

      assert result == ["", "A", "llo"]
    end

    test "when pattern is at the end of the string" do
      result = :string.replace("Hello", "lo", "p", :trailing)

      assert result == ["Hel", "p", ""]
    end

    test "with consecutive patterns" do
      result = :string.replace("lololo", "lo", "ha", :all)

      assert result == ["", "ha", "", "ha", "", "ha", ""]
    end

    # Input edge cases

    test "with empty pattern" do
      result = :string.replace("Hello World !", "", "_", :all)

      assert result == ["Hello World !"]
    end

    test "when pattern is not found" do
      result = :string.replace("Hello World !", ".", "_", :all)

      assert result == ["Hello World !"]
    end

    test "with empty replacement" do
      result = :string.replace("Hello World", " ", "", :all)

      assert result == ["Hello", "", "World"]
    end

    test "with unicode pattern" do
      result = :string.replace("Hello 👋 World", "👋", "🌍", :all)

      assert result == ["Hello ", "🌍", " World"]
    end

    # Replacement type variations

    test "accepts atom as replacement and inserts it as-is" do
      result = :string.replace("Hello World !", " ", :_, :all)

      assert result == ["Hello", :_, "World", :_, "!"]
    end

    test "accepts charlist as replacement and inserts it as-is" do
      result = :string.replace("Hello World !", " ", ~c"_", :all)

      assert result == ["Hello", ~c"_", "World", ~c"_", "!"]
    end

    # Error cases

    test "raises MatchError if the first argument is not valid chardata" do
      assert_error MatchError, build_match_error_msg(:hello_world), fn ->
        :string.replace(:hello_world, "_", " ", :all)
      end
    end

    test "raises ArgumentError if the second argument is not valid chardata" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :string.replace("Hello_World_!", :_, " ", :all)
                   end
    end

    test "raises CaseClauseError if the fourth argument is not an atom" do
      assert_error CaseClauseError, "no case clause matching: \"all\"", fn ->
        :string.replace("Hello World !", " ", "_", "all")
      end
    end

    test "raises CaseClauseError if the fourth argument is an unrecognized atom" do
      assert_error CaseClauseError, "no case clause matching: :invalid", fn ->
        :string.replace("Hello World", " ", "_", :invalid)
      end
    end
  end

  describe "split/2" do
    test "returns a two-elements list with the first word at the beginning and the tail at the end" do
      result = :string.split("Hello World !", " ")

      assert result == ["Hello", "World !"]
    end
  end

  describe "split/3" do
    test "with empty pattern" do
      result = :string.split("Hello World !", "", :all)

      assert result == ["Hello World !"]
    end

    test "with pattern not found in subject" do
      result = :string.split("Hello World !", ".", :all)

      assert result == ["Hello World !"]
    end

    test "with direction :all" do
      result = :string.split("Hello World !", " ", :all)

      assert result == ["Hello", "World", "!"]
    end

    test "with direction :leading" do
      result = :string.split("Hello World !", " ", :leading)

      assert result == ["Hello", "World !"]
    end

    test "with direction :trailing" do
      result = :string.split("Hello World !", " ", :trailing)

      assert result == ["Hello World", "!"]
    end

    test "with pattern at the start of the subject" do
      result = :string.split("Hello World !", "H", :leading)

      assert result == ["", "ello World !"]
    end

    test "with pattern at the end of the subject" do
      result = :string.split("Hello World !", "!", :trailing)

      assert result == ["Hello World ", ""]
    end

    test "with consecutive pattern" do
      result = :string.split("Hello World !", "l", :all)

      assert result == ["He", "", "o Wor", "d !"]
    end

    test "with unicode pattern" do
      result = :string.split("Hello 👋 World", "👋", :all)

      assert result == ["Hello ", " World"]
    end

    test "with charlist subject and charlist pattern" do
      result = :string.split(~c"Hello World", ~c" ", :all)

      assert result == [~c"Hello", ~c"World"]
    end

    test "with charlist subject and binary pattern" do
      result = :string.split(~c"Hello World", " ", :all)

      assert result == [~c"Hello", ~c"World"]
    end

    test "with binary subject and charlist pattern" do
      result = :string.split("Hello World", ~c" ", :all)

      assert result == ["Hello", "World"]
    end

    test "raises MatchError if the first argument is not valid chardata" do
      assert_error MatchError, build_match_error_msg(:hello_world), fn ->
        :string.split(:hello_world, "_", :all)
      end
    end

    test "raises ArgumentError if the second argument is not valid chardata" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not valid character data (an iodata term)"),
                   fn ->
                     :string.split("Hello_World_!", :_, :all)
                   end
    end

    test "raises CaseClauseError if the third argument is not an atom" do
      assert_error CaseClauseError, "no case clause matching: \"all\"", fn ->
        :string.split("Hello World !", " ", "all")
      end
    end

    test "raises CaseClauseError if the third argument is an unrecognized atom" do
      assert_error CaseClauseError, "no case clause matching: :invalid", fn ->
        :string.split("hello world", " ", :invalid)
      end
    end
  end

  describe "titlecase/1" do
    # Section: with binary input

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

    test "titlecases word without special case rules" do
      assert :string.titlecase("world") == "World"
    end

    test "raises ArgumentError for invalid UTF-8 binary" do
      invalid_binary = <<255, 255>>

      assert_error ArgumentError, "argument error: <<255, 255>>", fn ->
        :string.titlecase(invalid_binary)
      end
    end

    test "raises ArgumentError for surrogate pair codepoint" do
      # Create a binary with surrogate pair codepoint (55296)
      invalid_binary = <<0xED, 0xA0, 0x80>>

      assert_error ArgumentError, "argument error: <<237, 160, 128>>", fn ->
        :string.titlecase(invalid_binary)
      end
    end

    # Section: with list of integers (charlist)

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

    test "titlecases codepoint without special case rules" do
      assert :string.titlecase([119]) == [87]
    end

    test "does not validate surrogate pair codepoint in charlist" do
      # Erlang does not validate surrogate pairs in charlists
      assert :string.titlecase([55_296]) == [55_296]
    end

    # Section: with list starting with binary

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

    test "expands ligature ﬁ (64257) to nested list when binary has trailing content" do
      input = [<<64_257::utf8, "le">>]

      assert :string.titlecase(input) == [[70, 105], "le"]
    end

    test "expands ligature ﬁ (64257) to flat list when followed by separate binary" do
      input = [<<64_257::utf8>>, "ox"]

      assert :string.titlecase(input) == [70, 105, "", "ox"]
    end

    test "expands ligature ﬁ (64257) to flat list when alone in list" do
      input = [<<64_257::utf8>>]

      assert :string.titlecase(input) == [70, 105]
    end

    test "expands ligature ﬁ (64257) to flat list when followed by separate empty binary" do
      input = [<<64_257::utf8>>, ""]

      assert :string.titlecase(input) == [70, 105, "", ""]
    end

    test "expands ligature ﬁ (64257) to flat list when followed by separate integer" do
      input = [<<64_257::utf8>>, 97]

      assert :string.titlecase(input) == [70, 105, "", 97]
    end

    test "expands ligature ﬀ (64256) to nested list when binary has trailing content" do
      input = [<<64_256::utf8, "ox">>]

      assert :string.titlecase(input) == [[70, 102], "ox"]
    end

    test "expands ligature ﬀ (64256) to flat list when followed by separate binary" do
      input = [<<64_256::utf8>>, "ox"]

      assert :string.titlecase(input) == [70, 102, "", "ox"]
    end

    test "expands ligature ﬄ (64260) to nested list when binary has trailing content" do
      input = [<<64_260::utf8, "at">>]

      assert :string.titlecase(input) == [[70, 102, 108], "at"]
    end

    test "expands ligature ﬄ (64260) to flat list when followed by separate binary" do
      input = [<<64_260::utf8>>, "at"]

      assert :string.titlecase(input) == [70, 102, 108, "", "at"]
    end

    test "raises ArgumentError for invalid UTF-8 binary in list" do
      invalid_binary = <<255, 255>>

      assert_error ArgumentError, "argument error: <<255, 255>>", fn ->
        :string.titlecase([invalid_binary])
      end
    end

    test "returns empty list for empty binary in list" do
      assert :string.titlecase([""]) == []
    end

    # Section: with nested list

    test "processes nested list with single integer, rest is single integer" do
      assert :string.titlecase([[97], 98]) == [65, 98]
    end

    test "processes nested list with multiple integers, rest is multiple integers" do
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

    # Section: edge cases

    test "returns empty list for empty nested list" do
      assert :string.titlecase([[]]) == []
    end

    test "returns zero codepoint as-is" do
      assert :string.titlecase([0]) == [0]
    end

    test "returns large codepoint outside BMP as-is" do
      # 😀 emoji
      assert :string.titlecase([128_512]) == [128_512]
    end

    test "handles multiple empty binaries in list" do
      assert :string.titlecase(["", "", 97]) == [65]
    end

    test "handles nested list with empty binary" do
      assert :string.titlecase([[""], 97]) == [65]
    end

    test "raises FunctionClauseError for negative integer" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [-1])

      assert_error FunctionClauseError, expected_msg, fn ->
        :string.titlecase([-1])
      end
    end

    test "raises FunctionClauseError for very large integer" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [9_999_999])

      assert_error FunctionClauseError, expected_msg, fn ->
        :string.titlecase([9_999_999])
      end
    end

    test "raises FunctionClauseError for non-byte-aligned bitstring" do
      expected_msg =
        build_function_clause_error_msg(":string.titlecase/1", [<<1::1, 0::1, 1::1>>])

      assert_error FunctionClauseError, expected_msg, fn ->
        :string.titlecase(<<1::1, 0::1, 1::1>>)
      end
    end

    test "raises FunctionClauseError for list with non-byte-aligned bitstring" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [<<1::1, 0::1, 1::1>>])

      assert_error FunctionClauseError, expected_msg, fn ->
        :string.titlecase([<<1::1, 0::1, 1::1>>])
      end
    end

    # Section: error handling

    test "raises FunctionClauseError for integer input" do
      expected_msg = build_function_clause_error_msg(":string.titlecase/1", [42])

      assert_error FunctionClauseError, expected_msg, fn ->
        :string.titlecase(42)
      end
    end

    test "raises FunctionClauseError for atom input" do
      expected_msg = build_function_clause_error_msg(":string.titlecase/1", [:test])

      assert_error FunctionClauseError, expected_msg, fn ->
        :string.titlecase(:test)
      end
    end

    test "raises FunctionClauseError for float input" do
      expected_msg = build_function_clause_error_msg(":string.titlecase/1", [3.14])

      assert_error FunctionClauseError, expected_msg, fn ->
        :string.titlecase(3.14)
      end
    end

    test "raises FunctionClauseError for list with atom first element" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [:invalid])

      assert_error FunctionClauseError, expected_msg, fn ->
        :string.titlecase([:invalid])
      end
    end

    test "raises FunctionClauseError for list with float first element" do
      expected_msg = build_function_clause_error_msg(":unicode_util.cp/1", [3.14])

      assert_error FunctionClauseError, expected_msg, fn ->
        :string.titlecase([3.14])
      end
    end
  end
end
