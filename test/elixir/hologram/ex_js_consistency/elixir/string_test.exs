defmodule Hologram.ExJsConsistency.Elixir.StringTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/string_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

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
end
