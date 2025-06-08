defmodule Hologram.ExJsConsistency.Elixir.StringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/string_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "contains?/2, with a single pattern" do
    test "returns true when pattern is found" do
      assert String.contains?("hello world", "world")
    end

    test "returns false when pattern is not found" do
      refute String.contains?("hello world", "xyz")
    end

    test "returns true when subject is non-empty and pattern is empty" do
      assert String.contains?("hello", "")
    end

    test "returns true when subject is empty and pattern is empty" do
      assert String.contains?("", "")
    end

    test "returns false when subject is empty and pattern is non-empty" do
      refute String.contains?("", "test")
    end

    test "works with Unicode text" do
      assert String.contains?("全息图测试", "息图")
    end

    test "is case sensitive" do
      refute String.contains?("Hello World", "hello")
    end
  end

  describe "contains?/2, with multiple patterns" do
    test "returns true when first pattern is found" do
      assert String.contains?("hello world", ["world", "xyz", "abc"])
    end

    test "returns true when non-first pattern is found" do
      assert String.contains?("hello world", ["xyz", "world", "abc"])
    end

    test "returns true when multiple patterns are found" do
      assert String.contains?("hello world", ["hello", "world"])
    end

    test "returns false when no patterns are found" do
      refute String.contains?("hello world", ["xyz", "abc", "def"])
    end

    test "returns false when pattern list is empty" do
      refute String.contains?("hello world", [])
    end

    test "works with Unicode patterns" do
      assert String.contains?("全息图测试", ["ąćł", "测试"])
    end
  end

  describe "contains?/2, error cases" do
    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError when subject is not a bitstring" do
      expected_msg =
        build_function_clause_error_msg("String.contains?/2", [:hello, "test"], [
          "def contains?(string, contents) when -is_binary(string)- and -is_list(contents)-",
          "def contains?(string, contents) when -is_binary(string)-"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.contains?(:hello, "test")
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError when subject is a non-binary bitstring" do
      subject = <<1::1, 0::1, 1::1, 0::1>>

      expected_msg =
        build_function_clause_error_msg("String.contains?/2", [subject, "test"], [
          "def contains?(string, contents) when -is_binary(string)- and -is_list(contents)-",
          "def contains?(string, contents) when -is_binary(string)-"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.contains?(subject, "test")
      end
    end

    test "raises ArgumentError when pattern is invalid type" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a valid pattern"), fn ->
        String.contains?("hello world", 123)
      end
    end

    test "raises ArgumentError when pattern is a non-binary bitstring" do
      pattern = <<1::1, 0::1, 1::1, 0::1>>

      assert_error ArgumentError, build_argument_error_msg(2, "not a valid pattern"), fn ->
        String.contains?("hello world", pattern)
      end
    end

    test "raises ArgumentError when pattern list contains non-bitstring pattern" do
      patterns = ["hello", :world]

      assert_error ArgumentError, build_argument_error_msg(1, "not a bitstring"), fn ->
        String.contains?("hello world", patterns)
      end
    end

    test "raises ArgumentError when pattern list contains non-binary bitstring pattern" do
      patterns = ["hello", <<1::1, 0::1, 1::1, 0::1>>]

      assert_error ArgumentError, build_argument_error_msg(2, "not a valid pattern"), fn ->
        String.contains?("hello world", patterns)
      end
    end
  end

  describe "downcase/1" do
    test "delegates to downcase/2" do
      assert String.downcase("HoLoGrAm") == "hologram"
    end
  end

  describe "downcase/2" do
    test "default mode, ASCII string" do
      assert String.downcase("HoLoGrAm", :default) == "hologram"
    end

    test "default mode, Unicode string" do
      assert String.downcase("ŹRÓDŁO", :default) == "źródło"
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the first arg is not a bitstring" do
      expected_msg =
        build_function_clause_error_msg("String.downcase/2", [:abc, :default], [
          "def downcase(-\"\"-, _mode)",
          "def downcase(string, :default) when -is_binary(string)-",
          "def downcase(string, -:ascii-) when -is_binary(string)-",
          "def downcase(string, mode) when -is_binary(string)- and (-mode === :greek- or -mode === :turkic-)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.downcase(:abc, :default)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the first arg is a non-binary bitstring" do
      arg_1 = <<1::1, 0::1, 1::1, 0::1>>

      expected_msg =
        build_function_clause_error_msg("String.downcase/2", [arg_1, :default], [
          "def downcase(-\"\"-, _mode)",
          "def downcase(string, :default) when -is_binary(string)-",
          "def downcase(string, -:ascii-) when -is_binary(string)-",
          "def downcase(string, mode) when -is_binary(string)- and (-mode === :greek- or -mode === :turkic-)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.downcase(arg_1, :default)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the second arg is not an atom" do
      expected_msg =
        build_function_clause_error_msg("String.downcase/2", ["HoLoGrAm", 123], [
          "def downcase(-\"\"-, _mode)",
          "def downcase(string, -:default-) when is_binary(string)",
          "def downcase(string, -:ascii-) when is_binary(string)",
          "def downcase(string, mode) when is_binary(string) and (-mode === :greek- or -mode === :turkic-)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.downcase("HoLoGrAm", 123)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the second arg is an atom, but is not a valid mode" do
      expected_msg =
        build_function_clause_error_msg("String.downcase/2", ["HoLoGrAm", :abc], [
          "def downcase(-\"\"-, _mode)",
          "def downcase(string, -:default-) when is_binary(string)",
          "def downcase(string, -:ascii-) when is_binary(string)",
          "def downcase(string, mode) when is_binary(string) and (-mode === :greek- or -mode === :turkic-)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.downcase("HoLoGrAm", :abc)
      end
    end
  end

  describe "replace/3" do
    test "ASCII text" do
      assert String.replace("abcabc", "ab", "xy") == "xycxyc"
    end

    test "Unicode text" do
      assert String.replace("全息图全息图", "全息", "xy") == "xy图xy图"
    end

    test "grapheme 'é' which is made of the characters 'e' and the acute accent (replacing across grapheme boundaries)" do
      assert String.replace("é", "e", "o") == "ó"
    end

    test "grapheme 'é' which is represented by the single character 'e with acute' accent (no replacing at all)" do
      assert String.replace("é", "e", "o") == "é"
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "non-binary subject arg" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg("String.replace/4", [:abc, "ab", "xy", []], [
                     "def replace(subject, pattern, replacement, options) when -is_binary(subject)- and (is_binary(replacement) or -is_function(replacement, 1)-) and is_list(options)"
                   ]),
                   fn ->
                     String.replace(:abc, "ab", "xy")
                   end
    end
  end

  describe "trim/1" do
    test "handles empty bitstrings" do
      assert String.trim("") == ""
    end

    test "trims non-empty bitstrings" do
      assert String.trim("  \n\tabc\t\n  ") == "abc"
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the arg is a non-binary bitstring" do
      bitstring = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>

      expected_msg =
        build_function_clause_error_msg("String.trim/1", [bitstring], [
          "def trim(string) when -is_binary(string)-"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.trim(bitstring)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the arg is not a bitstring" do
      expected_msg =
        build_function_clause_error_msg("String.trim/1", [:abc], [
          "def trim(string) when -is_binary(string)-"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.trim(:abc)
      end
    end
  end

  describe "upcase/1" do
    test "delegates to upcase/2" do
      assert String.upcase("HoLoGrAm") == "HOLOGRAM"
    end
  end

  describe "upcase/2" do
    test "default mode, ASCII string" do
      assert String.upcase("HoLoGrAm", :default) == "HOLOGRAM"
    end

    test "default mode, Unicode string" do
      assert String.upcase("źródło", :default) == "ŹRÓDŁO"
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the first arg is not a bitstring" do
      expected_msg =
        build_function_clause_error_msg("String.upcase/2", [:abc, :default], [
          "def upcase(-\"\"-, _mode)",
          "def upcase(string, :default) when -is_binary(string)-",
          "def upcase(string, -:ascii-) when -is_binary(string)-",
          "def upcase(string, mode) when -is_binary(string)- and (-mode === :greek- or -mode === :turkic-)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.upcase(:abc, :default)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the first arg is a non-binary bitstring" do
      arg_1 = <<1::1, 0::1, 1::1, 0::1>>

      expected_msg =
        build_function_clause_error_msg("String.upcase/2", [arg_1, :default], [
          "def upcase(-\"\"-, _mode)",
          "def upcase(string, :default) when -is_binary(string)-",
          "def upcase(string, -:ascii-) when -is_binary(string)-",
          "def upcase(string, mode) when -is_binary(string)- and (-mode === :greek- or -mode === :turkic-)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.upcase(arg_1, :default)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the second arg is not an atom" do
      expected_msg =
        build_function_clause_error_msg("String.upcase/2", ["HoLoGrAm", 123], [
          "def upcase(-\"\"-, _mode)",
          "def upcase(string, -:default-) when is_binary(string)",
          "def upcase(string, -:ascii-) when is_binary(string)",
          "def upcase(string, mode) when is_binary(string) and (-mode === :greek- or -mode === :turkic-)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.upcase("HoLoGrAm", 123)
      end
    end

    # TODO: client error message for this case is inconsistent with server error message
    test "raises FunctionClauseError if the second arg is an atom, but is not a valid mode" do
      expected_msg =
        build_function_clause_error_msg("String.upcase/2", ["HoLoGrAm", :abc], [
          "def upcase(-\"\"-, _mode)",
          "def upcase(string, -:default-) when is_binary(string)",
          "def upcase(string, -:ascii-) when is_binary(string)",
          "def upcase(string, mode) when is_binary(string) and (-mode === :greek- or -mode === :turkic-)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        String.upcase("HoLoGrAm", :abc)
      end
    end
  end
end
