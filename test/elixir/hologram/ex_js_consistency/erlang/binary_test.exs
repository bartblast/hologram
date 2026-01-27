defmodule Hologram.ExJsConsistency.Erlang.BinaryTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/binary_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  @binary <<5, 19, 72, 33>>

  # Erlang/OTP 27 on Linux with Elixir 1.18.x returns a more specific error message
  # for invalid scope in :binary.match/3. Other combinations return "invalid options".
  defp binary_match_invalid_scope_error_msg do
    otp_release = String.to_integer(System.otp_release())
    %{major: major, minor: minor} = Version.parse!(System.version())
    elixir_1_18? = major == 1 and minor == 18
    {os_type, _os_name} = :os.type()

    if os_type == :unix and otp_release == 27 and elixir_1_18? do
      build_argument_error_msg(3, "specified part is not wholly inside binary")
    else
      build_argument_error_msg(3, "invalid options")
    end
  end

  describe "at/2" do
    test "returns first byte" do
      assert :binary.at(@binary, 0) == 5
    end

    test "returns middle byte" do
      assert :binary.at(@binary, 1) == 19
    end

    test "returns last byte" do
      assert :binary.at(@binary, 3) == 33
    end

    test "raises ArgumentError when position is out of range" do
      assert_error ArgumentError, "argument error", fn ->
        :binary.at(@binary, 4)
      end
    end

    test "raises ArgumentError when subject is nil" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   fn -> :binary.at(nil, 0) end
    end

    test "raises ArgumentError when bitstring is not a binary" do
      subject = <<1::1, 0::1, 1::1>>

      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   fn -> :binary.at(subject, 0) end
    end

    test "raises ArgumentError when position is nil" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   fn -> :binary.at(@binary, nil) end
    end

    test "raises ArgumentError when position is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   fn -> :binary.at(@binary, -1) end
    end
  end

  describe "compile_pattern/1" do
    # With valid input

    test "single binary pattern returns Boyer-Moore compiled pattern tuple" do
      result = :binary.compile_pattern("Hello")

      assert is_tuple(result)
      assert elem(result, 0) == :bm
      assert is_reference(elem(result, 1))
    end

    test "list of binary patterns returns Aho-Corasick compiled pattern tuple" do
      result = :binary.compile_pattern(["He", "llo"])

      assert is_tuple(result)
      assert elem(result, 0) == :ac
      assert is_reference(elem(result, 1))
    end

    test "list with single element returns Boyer-Moore compiled pattern tuple" do
      result = :binary.compile_pattern(["Hello"])

      assert is_tuple(result)
      assert elem(result, 0) == :bm
      assert is_reference(elem(result, 1))
    end

    # Errors with direct pattern

    test "raises ArgumentError when pattern is not bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern(1) end
    end

    test "raises ArgumentError when pattern is non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern(<<1::1, 0::1, 1::1>>) end
    end

    test "raises ArgumentError when pattern is empty binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern("") end
    end

    test "raises ArgumentError when pattern is empty list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern([]) end
    end

    # Errors with list containing invalid item

    test "raises ArgumentError when pattern is list containing non-bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern(["Hello", 1]) end
    end

    test "raises ArgumentError when pattern is list containing non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern(["Hello", <<1::1, 0::1, 1::1>>]) end
    end

    test "raises ArgumentError when pattern is list containing empty binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern(["Hello", ""]) end
    end

    test "raises ArgumentError when pattern is list containing empty list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a valid pattern"),
                   fn -> :binary.compile_pattern(["Hello", []]) end
    end
  end

  describe "copy/2" do
    test "text-based, empty binary, zero times" do
      assert :binary.copy("", 0) == ""
    end

    test "text-based, empty binary, one time" do
      assert :binary.copy("", 1) == ""
    end

    test "text-based, empty binary, multiple times" do
      assert :binary.copy("", 3) == ""
    end

    test "text-based, non-empty binary, zero times" do
      assert :binary.copy("hello", 0) == ""
    end

    test "text-based, non-empty binary, one time" do
      assert :binary.copy("hello", 1) == "hello"
    end

    test "text-based, non-empty binary, multiple times" do
      assert :binary.copy("hello", 3) == "hellohellohello"
    end

    test "bytes-based, empty binary, zero times" do
      assert :binary.copy(<<>>, 0) == <<>>
    end

    test "bytes-based, empty binary, one time" do
      assert :binary.copy(<<>>, 1) == <<>>
    end

    test "bytes-based, empty binary, multiple times" do
      assert :binary.copy(<<>>, 3) == <<>>
    end

    test "bytes-based, non-empty binary, zero times" do
      assert :binary.copy(<<65, 66, 67>>, 0) == <<>>
    end

    test "bytes-based, non-empty binary, one time" do
      assert :binary.copy(<<65, 66, 67>>, 1) == <<65, 66, 67>>
    end

    test "bytes-based, non-empty binary, multiple times" do
      result = :binary.copy(<<65, 66, 67>>, 3)
      expected = <<65, 66, 67, 65, 66, 67, 65, 66, 67>>

      assert result == expected
    end

    test "raises ArgumentError if the first argument is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :copy, [:abc, 3]}
    end

    test "raises ArgumentError if the first argument is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :copy, [<<1::1, 0::1, 1::1>>, 3]}
    end

    test "raises ArgumentError if the second argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   {:binary, :copy, ["hello", :abc]}
    end

    test "raises ArgumentError if count is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   {:binary, :copy, ["hello", -1]}
    end
  end

  describe "first/1" do
    test "returns first byte of a single-byte binary" do
      assert :binary.first(<<42>>) == 42
    end

    test "returns first byte of a multi-byte binary" do
      assert :binary.first(<<5, 4, 3>>) == 5
    end

    test "returns first byte of a text-based binary" do
      assert :binary.first("ELIXIR") == 69
    end

    test "returns first byte of UTF-8 multi-byte character" do
      assert :binary.first("é") == 195
    end

    test "raises ArgumentError if subject is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :first, [123]}
    end

    test "raises ArgumentError if subject is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :first, [<<1::1, 0::1, 1::1>>]}
    end

    test "raises ArgumentError if subject is an empty binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "a zero-sized binary is not allowed"),
                   {:binary, :first, [<<>>]}
    end
  end

  describe "last/1" do
    test "returns last byte of a single-byte binary" do
      assert :binary.last(<<42>>) == 42
    end

    test "returns last byte of a multi-byte binary" do
      assert :binary.last(@binary) == 33
    end

    test "returns last byte of a text-based binary" do
      assert :binary.last("ELIXIR") == 82
    end

    test "returns last byte of UTF-8 multi-byte character" do
      assert :binary.last("é") == 169
    end

    test "raises ArgumentError if subject is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :last, [:abc]}
    end

    test "raises ArgumentError if subject is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :last, [<<1::1, 0::1, 1::1>>]}
    end

    test "raises ArgumentError if subject is an empty binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "a zero-sized binary is not allowed"),
                   {:binary, :last, [""]}
    end
  end

  describe "match/2" do
    test "delegates to match/3 with empty options" do
      # Verifies default options (no :global) - finds first match only
      assert :binary.match("hello world world", "world") == {6, 5}
    end
  end

  describe "match/3" do
    # Finding patterns

    test "finds single pattern at start" do
      assert :binary.match("the rain in spain", "the", []) == {0, 3}
    end

    test "finds single pattern in middle" do
      assert :binary.match("the rain in spain", "ain", []) == {5, 3}
    end

    test "finds single pattern at end" do
      assert :binary.match("hello world", "world", []) == {6, 5}
    end

    test "returns nomatch when pattern not found" do
      assert :binary.match("hello world", "xyz", []) == :nomatch
    end

    test "finds first occurrence when multiple matches exist" do
      assert :binary.match("abcabc", "abc", []) == {0, 3}
    end

    test "works with multi-byte patterns" do
      assert :binary.match("foo123bar", "123", []) == {3, 3}
    end

    test "finds first match with multiple patterns" do
      assert :binary.match("abcde", ["bcde", "cd"], []) == {1, 4}
    end

    test "returns longest match when patterns start at same position" do
      assert :binary.match("abcde", ["ab", "abcd"], []) == {0, 4}
    end

    test "returns longest match with three or more overlapping patterns" do
      assert :binary.match("abcdefgh", ["ab", "abc", "abcd", "abcde"], []) == {0, 5}
    end

    test "works with compiled pattern" do
      compiled = :binary.compile_pattern("world")

      assert :binary.match("hello world", compiled, []) == {6, 5}
    end

    test "works with bytes-based binary" do
      assert :binary.match(<<1, 2, 3, 4, 5>>, <<3, 4>>, []) == {2, 2}
    end

    test "returns nomatch when subject is empty" do
      assert :binary.match("", "a", []) == :nomatch
    end

    test "returns nomatch when pattern is longer than subject" do
      assert :binary.match("ab", "abcdef", []) == :nomatch
    end

    # Scope option - valid cases

    test "returns nomatch when pattern exists but not within scope" do
      assert :binary.match("hello world", "world", scope: {0, 3}) == :nomatch
    end

    test "respects scope start position" do
      assert :binary.match("the rain in spain", "ain", scope: {5, 8}) == {5, 3}
    end

    test "finds match at start of scope" do
      assert :binary.match("abcdef", "cd", scope: {2, 4}) == {2, 2}
    end

    test "returns nomatch when pattern outside scope" do
      assert :binary.match("hello world", "world", scope: {0, 5}) == :nomatch
    end

    test "returns nomatch when scope length is zero" do
      assert :binary.match("hello", "h", scope: {0, 0}) == :nomatch
    end

    test "accepts negative scope length (reverse part)" do
      subject = "hello world"
      opts = [scope: {byte_size(subject), -5}]

      assert :binary.match(subject, "world", opts) == {6, 5}
    end

    # With empty options list

    test "works with empty options list" do
      assert :binary.match("test", "es", []) == {1, 2}
    end

    # Input validation

    test "raises ArgumentError if subject is not a binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :match, [:not_binary, "test", []]}
    end

    test "raises ArgumentError if subject is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :match, [<<1::1, 0::1, 1::1>>, "test", []]}
    end

    test "raises ArgumentError when pattern is empty" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :match, ["test", "", []]}
    end

    test "raises ArgumentError with empty pattern list" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :match, ["test", [], []]}
    end

    test "raises ArgumentError if pattern is not a binary or list" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :match, ["test", :invalid, []]}
    end

    test "raises ArgumentError if pattern list contains non-binary element" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :match, ["test", ["ok", :bad], []]}
    end

    test "raises ArgumentError with invalid compiled pattern reference" do
      invalid_ref = make_ref()

      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :match, ["test", {:bm, invalid_ref}, []]}
    end

    # Options validation

    test "raises ArgumentError if options is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :match, ["test", "es", :invalid]}
    end

    test "raises ArgumentError if options is an improper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :match, ["test", "es", [:global | :tail]]}
    end

    test "raises ArgumentError with unknown atom option" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :match, ["test", "es", [:unknown]]}
    end

    test "raises ArgumentError with malformed scope tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :match, ["test", "es", [scope: :bad]]}
    end

    test "raises ArgumentError when scope start exceeds subject length" do
      assert_error ArgumentError,
                   binary_match_invalid_scope_error_msg(),
                   {:binary, :match, ["test", "t", [scope: {10, 1}]]}
    end

    test "raises ArgumentError when scope extends beyond subject" do
      assert_error ArgumentError,
                   binary_match_invalid_scope_error_msg(),
                   {:binary, :match, ["test", "st", [scope: {0, 100}]]}
    end

    test "raises ArgumentError with negative scope start" do
      assert_error ArgumentError,
                   binary_match_invalid_scope_error_msg(),
                   {:binary, :match, ["test", "es", [scope: {-1, 2}]]}
    end

    test "raises ArgumentError when scope start plus negative length is below zero" do
      assert_error ArgumentError,
                   binary_match_invalid_scope_error_msg(),
                   {:binary, :match, ["test", "es", [scope: {0, -1}]]}
    end

    test "raises ArgumentError with non-integer scope start" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :match, ["test", "es", [scope: {:bad, 2}]]}
    end

    test "raises ArgumentError with non-integer scope length" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :match, ["test", "es", [scope: {0, :bad}]]}
    end
  end

  describe "matches/2" do
    test "delegates to matches/3 with empty options" do
      assert :binary.matches("the rain in spain", "ai") == [{5, 2}, {14, 2}]
    end
  end

  describe "matches/3" do
    # Finding patterns

    test "returns all non-overlapping matches" do
      assert :binary.matches("banana bandana", "ana", []) == [{1, 3}, {11, 3}]
    end

    test "returns non-overlapping repeated matches" do
      assert :binary.matches("aaaa", "aa", []) == [{0, 2}, {2, 2}]
    end

    test "prefers longer match when starting at same position" do
      assert :binary.matches("abcde", ["bcde", "bc", "de"], []) == [{1, 4}]
    end

    test "works with compiled pattern" do
      compiled = :binary.compile_pattern("ai")

      assert :binary.matches("the rain in spain", compiled, []) == [{5, 2}, {14, 2}]
    end

    test "works with bytes-based binary" do
      assert :binary.matches(<<1, 2, 3, 2, 3, 4>>, <<2, 3>>, []) == [{1, 2}, {3, 2}]
    end

    test "works with compiled Aho-Corasick pattern" do
      compiled = :binary.compile_pattern(["ab", "bc"])

      assert :binary.matches("zabcbc", compiled, []) == [{1, 2}, {4, 2}]
    end

    test "returns empty list when no matches" do
      assert :binary.matches("hello", "xyz", []) == []
    end

    test "returns empty list when subject is empty" do
      assert :binary.matches("", "a", []) == []
    end

    test "returns empty list when pattern is longer than subject" do
      assert :binary.matches("ab", "abcdef", []) == []
    end

    # Scope option

    test "finds matches only within scope" do
      assert :binary.matches("the rain in spain", "ai", scope: {4, 6}) == [{5, 2}]
    end

    test "returns empty list when scope length is zero" do
      assert :binary.matches("abc", "a", scope: {0, 0}) == []
    end

    test "supports negative scope length" do
      subject = "hello world"
      opts = [scope: {byte_size(subject), -5}]

      assert :binary.matches(subject, "wo", opts) == [{6, 2}]
    end

    # Input validation

    test "raises ArgumentError if subject is not a binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :matches, [:not_binary, "a", []]}
    end

    test "raises ArgumentError if subject is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :matches, [<<1::1, 0::1, 1::1>>, "a", []]}
    end

    test "raises ArgumentError when pattern is invalid" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :matches, ["abc", "", []]}
    end

    test "raises ArgumentError with empty pattern list" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :matches, ["test", [], []]}
    end

    test "raises ArgumentError if pattern list contains non-binary element" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :matches, ["test", ["ok", :bad], []]}
    end

    test "raises ArgumentError with missing compiled pattern data" do
      invalid_pattern = {:bm, make_ref()}

      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   fn -> :binary.matches("abc", invalid_pattern, []) end
    end

    # Options validation

    test "raises ArgumentError if options is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :matches, ["abc", "a", :bad]}
    end

    test "raises ArgumentError for improper list options" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :matches, ["abc", "a", [:scope | :tail]]}
    end

    test "raises ArgumentError when unsupported option provided" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :matches, ["abc", "a", [:global]]}
    end

    test "raises ArgumentError with malformed scope" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :matches, ["abc", "a", [scope: :bad]]}
    end

    test "raises ArgumentError when scope is out of range" do
      assert_error ArgumentError,
                   binary_match_invalid_scope_error_msg(),
                   {:binary, :matches, ["abc", "a", [scope: {10, 1}]]}
    end

    test "raises ArgumentError when scope extends beyond subject" do
      assert_error ArgumentError,
                   binary_match_invalid_scope_error_msg(),
                   {:binary, :matches, ["abc", "a", [scope: {0, 10}]]}
    end

    test "raises ArgumentError when scope start is negative" do
      assert_error ArgumentError,
                   binary_match_invalid_scope_error_msg(),
                   {:binary, :matches, ["abc", "a", [scope: {-1, 2}]]}
    end

    test "raises ArgumentError when scope start plus negative length is below zero" do
      assert_error ArgumentError,
                   binary_match_invalid_scope_error_msg(),
                   {:binary, :matches, ["abc", "a", [scope: {0, -1}]]}
    end

    test "raises ArgumentError when scope length is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :matches, ["abc", "a", [scope: {0, :bad}]]}
    end

    test "raises ArgumentError when scope elements are not integers" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   {:binary, :matches, ["abc", "a", [scope: {:bad, 1}]]}
    end
  end

  describe "split/2" do
    # Verifies default options (no :global) - splits only on first match
    test "delegates to split/3 with empty options" do
      assert :binary.split("hello world world", " ") == ["hello", "world world"]
    end
  end

  describe "split/3" do
    # With :global option

    test "splits on all occurrences with :global" do
      assert :binary.split("hello world world", " ", [:global]) == [
               "hello",
               "world",
               "world"
             ]
    end

    test "splits with multiple patterns globally" do
      assert :binary.split("hello-world_test", ["-", "_"], [:global]) == [
               "hello",
               "world",
               "test"
             ]
    end

    test "handles consecutive patterns with :global" do
      assert :binary.split("a--b--c", "-", [:global]) == ["a", "", "b", "", "c"]
    end

    test "handles pattern at start, middle, and end" do
      assert :binary.split("-a-", "-", [:global]) == ["", "a", ""]
    end

    test "handles invalid UTF-8 sequences in result with :global" do
      # Create binary with invalid UTF-8: <<65, 255, 66>> where 255 is invalid standalone
      subject = <<65, 32, 255, 32, 66>>
      result = :binary.split(subject, " ", [:global])

      assert length(result) == 3
      assert Enum.at(result, 0) == <<65>>
      assert Enum.at(result, 1) == <<255>>
      assert Enum.at(result, 2) == <<66>>
    end

    # Without :global option

    test "splits only on first occurrence without :global" do
      assert :binary.split("hello-world-test", "-", []) == ["hello", "world-test"]
    end

    test "splits with multi-byte pattern" do
      assert :binary.split("aaabbbccc", "bb", []) == ["aaa", "bccc"]
    end

    test "returns list with original binary when pattern not found" do
      assert :binary.split("test", "x", []) == ["test"]
    end

    test "splits with multiple patterns" do
      assert :binary.split("hello-world_test", ["-", "_"], []) == ["hello", "world_test"]
    end

    test "handles empty subject" do
      assert :binary.split("", "x", []) == [""]
    end

    # Compiled pattern behavior

    test "splits using compiled Boyer-Moore pattern" do
      compiled_pattern = :binary.compile_pattern("world")

      assert :binary.split("hello world", compiled_pattern, []) == [
               "hello ",
               ""
             ]
    end

    test "splits using compiled Aho-Corasick pattern" do
      compiled_pattern = :binary.compile_pattern(["-", "o"])

      assert :binary.split("hello-world", compiled_pattern, [:global]) == [
               "hell",
               "",
               "w",
               "rld"
             ]
    end

    test "raises ArgumentError when compiled pattern data is missing" do
      invalid_pattern = {:bm, make_ref()}

      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   fn -> :binary.split("hello", invalid_pattern, []) end
    end

    # Options: :trim and :trim_all

    test "applies :trim to remove trailing empties only" do
      assert :binary.split("-a-", "-", [:global, :trim]) == ["", "a"]
    end

    test "applies :trim_all to remove all empty parts" do
      assert :binary.split("-a-", "-", [:global, :trim_all]) == ["a"]
    end

    test "returns empty list when empty subject with :trim" do
      assert :binary.split("", " ", [:global, :trim]) == []
    end

    # Options: scope

    test "respects scope option when a match exists in the range" do
      assert :binary.split("abc", "b", scope: {1, 1}) == ["a", "c"]
    end

    test "returns original binary when scope excludes the pattern" do
      assert :binary.split("abc", "b", scope: {0, 1}) == ["abc"]
    end

    test "returns original binary when scope length is zero" do
      assert :binary.split("abc", "b", scope: {1, 0}) == ["abc"]
    end

    test "works with scope and multiple patterns" do
      assert :binary.split("hello-world", ["-", "o"], [{:scope, {0, 11}}, :global]) == [
               "hell",
               "",
               "w",
               "rld"
             ]
    end

    test "works with scope and :trim option" do
      assert :binary.split("a-b--", "-", [{:scope, {0, 5}}, :global, :trim]) == ["a", "b"]
    end

    test "collects trailing bytes after loop exits naturally with global split" do
      assert :binary.split("a-b-c-", "-", [{:scope, {0, 5}}, :global]) == ["a", "b", "c-"]
    end

    test "collects trailing bytes when scope is exhausted in global split" do
      assert :binary.split("abcdef", "d", [{:scope, {1, 3}}, :global]) == ["abc", "ef"]
    end

    test "accepts negative scope length (reverse part)" do
      subject = "hello world"
      opts = [scope: {byte_size(subject), -6}]

      assert :binary.split(subject, " ", opts) == ["hello", "world"]
    end

    # Overlapping patterns

    test "with overlapping patterns, matches first found" do
      assert :binary.split("abcabc", ["ab", "abc"], [:global]) == ["", "", ""]
    end

    # Error cases

    test "raises ArgumentError when subject is not bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   fn -> :binary.split(:test, " ", []) end
    end

    test "raises ArgumentError when subject is non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   fn -> :binary.split(<<1::1, 0::1, 1::1>>, " ", []) end
    end

    test "raises ArgumentError when pattern is not bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   fn -> :binary.split("test", 123, []) end
    end

    test "raises ArgumentError when pattern is non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   fn -> :binary.split("test", <<1::1, 0::1, 1::1>>, []) end
    end

    test "raises ArgumentError when pattern is empty string" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   fn -> :binary.split("test", "", []) end
    end

    test "raises ArgumentError when pattern is empty list" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   fn -> :binary.split("test", [], []) end
    end

    test "raises ArgumentError when pattern is list with non-bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   fn -> :binary.split("test", ["a", :b], []) end
    end

    test "raises ArgumentError when pattern is list with non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   fn -> :binary.split("test", ["a", <<1::1, 0::1, 1::1>>], []) end
    end

    test "raises ArgumentError when pattern is list with empty string" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   fn -> :binary.split("test", ["a", ""], []) end
    end

    test "raises ArgumentError when options is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :binary.split("hello world", " ", :invalid) end
    end

    test "raises ArgumentError for improper list options" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :binary.split("abc", "b", [:test | :tail]) end
    end

    test "raises ArgumentError for negative scope start" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :binary.split("abc", "b", scope: {-1, 2}) end
    end

    test "raises ArgumentError for scope start beyond subject length" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :binary.split("abc", "b", scope: {10, 5}) end
    end

    test "raises ArgumentError for scope extending beyond subject length" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "invalid options"),
                   fn -> :binary.split("abc", "b", scope: {1, 3}) end
    end
  end

  describe "replace/3" do
    test "delegates to replace/4 with empty options list" do
      assert :binary.replace("hello world", "world", "universe") == "hello universe"
    end
  end

  describe "replace/4" do
    # Basic replacement

    test "replaces first occurrence of pattern" do
      assert :binary.replace("hello world world", "world", "universe", []) ==
               "hello universe world"
    end

    test "returns original subject when pattern not found" do
      assert :binary.replace("hello world", "xyz", "abc", []) == "hello world"
    end

    test "replaces single pattern with multiple patterns in list" do
      assert :binary.replace("hello world", ["world", "hello"], "X", []) == "X world"
    end

    test "works with empty replacement" do
      assert :binary.replace("hello world", "world", "", []) == "hello "
    end

    test "works with bytes-based binaries" do
      assert :binary.replace(<<1, 2, 3, 4, 5>>, <<3, 4>>, <<9, 9>>, []) ==
               <<1, 2, 9, 9, 5>>
    end

    # With :global option

    test "replaces all occurrences with :global" do
      assert :binary.replace("hello world world", "world", "universe", [:global]) ==
               "hello universe universe"
    end

    test "replaces with multiple patterns globally" do
      assert :binary.replace("hello-world_test", ["-", "_"], "X", [:global]) ==
               "helloXworldXtest"
    end

    test "handles consecutive patterns with :global" do
      assert :binary.replace("a--b--c", "-", "X", [:global]) == "aXXbXXc"
    end

    test "handles empty replacement with :global" do
      assert :binary.replace("a1b1c1", "1", "", [:global]) == "abc"
    end

    # With insert_replaced option

    test "inserts matched part at single position" do
      assert :binary.replace("abcde", "bcd", "[", insert_replaced: 1) == "a[bcde"
    end

    test "inserts matched part at beginning" do
      assert :binary.replace("hello world", "world", "[]", insert_replaced: 0) ==
               "hello world[]"
    end

    test "inserts matched part at end" do
      assert :binary.replace("hello world", "world", "[]", insert_replaced: 2) ==
               "hello []world"
    end

    test "inserts matched part at multiple positions" do
      assert :binary.replace("abcde", "cd", "[]", insert_replaced: [1, 1]) ==
               "ab[cdcd]e"
    end

    test "works with :global and insert_replaced" do
      subject = "a-a-a"

      result =
        :binary.replace(
          subject,
          "a",
          "x",
          [:global, {:insert_replaced, 1}]
        )

      expected_binary = "xa-xa-xa"
      expected_positions = [0, 2, 4]

      assert result == expected_binary

      assert {result, expected_positions} ==
               {expected_binary,
                subject
                |> :binary.matches("a")
                |> Enum.map(&elem(&1, 0))}
    end

    # With replacement function

    test "uses function for replacement" do
      assert :binary.replace("hello world", "world", fn m -> "[" <> m <> "]" end, []) ==
               "hello [world]"
    end

    test "calls function for each match with :global" do
      result = :binary.replace("abcabc", "ab", fn _m -> "X" end, [:global])

      assert result == "XcXc"
    end

    test "function receives matched binary" do
      result =
        :binary.replace(
          <<1, 2, 3>>,
          <<2>>,
          fn _matched -> <<9>> end,
          []
        )

      assert result == <<1, 9, 3>>
    end

    test "raises error if function returns non-binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   fn ->
                     :binary.replace("hello", "l", fn _matched -> :not_binary end, [])
                   end
    end

    # With scope option

    test "respects scope when replacing" do
      assert :binary.replace("abc def abc", "abc", "X", scope: {8, 3}) == "abc def X"
    end

    test "replaces pattern within scope" do
      assert :binary.replace("abc def abc", "abc", "X", scope: {0, 3}) == "X def abc"
    end

    test "handles scope with global" do
      assert :binary.replace("abc def abc ghi abc", "abc", "X", [{:scope, {0, 15}}, :global]) ==
               "X def X ghi abc"
    end

    test "returns original subject when scope length is zero" do
      result =
        :binary.replace("hello world", "world", "universe", scope: {0, 0})

      assert result == "hello world"
    end

    # With compiled pattern

    test "works with compiled Boyer-Moore pattern" do
      compiled = :binary.compile_pattern("world")

      assert :binary.replace("hello world", compiled, "universe", []) == "hello universe"
    end

    test "works with compiled Aho-Corasick pattern" do
      compiled = :binary.compile_pattern(["-", "o"])

      assert :binary.replace("hello-world", compiled, "X", [:global]) == "hellXXwXrld"
    end

    # Error cases

    test "raises ArgumentError if subject is not a binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:binary, :replace, [:test, "test", "x", []]}
    end

    test "raises ArgumentError if subject is non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "is a bitstring (expected a binary)"),
                   {:binary, :replace, [<<1::1, 0::1, 1::1>>, "test", "x", []]}
    end

    test "raises ArgumentError when pattern is empty" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :replace, ["test", "", "x", []]}
    end

    test "raises ArgumentError when insert_replaced position exceeds replacement length" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["hello", "l", "X", [insert_replaced: 10]]}
    end

    test "raises ArgumentError for invalid options" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["test", "es", "x", :invalid]}
    end

    test "raises ArgumentError when scope start exceeds subject length" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["test", "t", "x", [scope: {10, 1}]]}
    end

    test "raises ArgumentError when scope extends beyond subject" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["test", "st", "x", [scope: {0, 100}]]}
    end

    test "raises ArgumentError when replacement is an atom" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a valid replacement"),
                   {:binary, :replace, ["hello", "l", :invalid, []]}
    end

    test "raises ArgumentError when replacement is an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a valid replacement"),
                   {:binary, :replace, ["hello", "l", 123, []]}
    end

    test "raises ArgumentError when replacement is a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a valid replacement"),
                   {:binary, :replace, ["hello", "l", [1], []]}
    end

    test "raises ArgumentError when pattern is a list with non-binary element" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :replace, ["hello", ["l", :invalid], "X", []]}
    end

    test "raises ArgumentError when pattern is an empty list" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a valid pattern"),
                   {:binary, :replace, ["hello", [], "X", []]}
    end

    test "raises ArgumentError when insert_replaced has negative position" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["hello", "l", "[]", [insert_replaced: -1]]}
    end

    test "raises ArgumentError when insert_replaced value is an atom" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["hello", "l", "[]", [insert_replaced: :invalid]]}
    end

    test "raises ArgumentError when insert_replaced list contains non-integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["hello", "l", "[]", [insert_replaced: [1, :invalid]]]}
    end

    test "raises ArgumentError when insert_replaced is an improper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["hello", "l", "[]", [insert_replaced: [1 | 2]]]}
    end

    test "raises ArgumentError when insert_replaced list contains negative integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["hello", "l", "[]", [insert_replaced: [1, -1]]]}
    end

    test "raises ArgumentError when scope start is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(4, "invalid options"),
                   {:binary, :replace, ["hello", "l", "X", [scope: {-1, 5}]]}
    end

    # Edge cases

    test "works with empty subject" do
      assert :binary.replace("", "x", "y", []) == ""
    end

    test "works when pattern equals entire subject" do
      assert :binary.replace("hello", "hello", "world", []) == "world"
    end

    test "works when replacement is longer than pattern" do
      assert :binary.replace("hi", "i", "ello world", []) == "hello world"
    end

    test "works when replacement is shorter than pattern" do
      assert :binary.replace("hello world", "hello", "hi", []) == "hi world"
    end

    test "works with single character subject" do
      assert :binary.replace("a", "a", "b", []) == "b"
    end
  end
end
