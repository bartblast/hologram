defmodule Elixir.Hologram.ExJsConsistency.Erlang.ElixirUtilsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/elixir_utils_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  if Version.match?(System.version(), ">= 1.17.0") do
    describe "jaro_similarity/2" do
      test "returns 1.0 for identical strings" do
        assert :elixir_utils.jaro_similarity("hello", "hello") == 1.0
      end

      test "returns 1.0 when both inputs are empty" do
        assert :elixir_utils.jaro_similarity("", "") == 1.0
      end

      test "returns 0.0 for completely different inputs" do
        assert :elixir_utils.jaro_similarity("abc", "xyz") == 0.0
      end

      test "returns 0.0 when first input is empty" do
        assert :elixir_utils.jaro_similarity("", "hello") == 0.0
      end

      test "returns 0.0 when second input is empty" do
        assert :elixir_utils.jaro_similarity("hello", "") == 0.0
      end

      test "returns 0.0 for identical single characters" do
        # Known issue in :elixir_utils.jaro_similarity/2.
        # Elixir will eventually switch to :string.jaro_similarity/2
        # when it requires Erlang/OTP 27+.
        assert :elixir_utils.jaro_similarity("a", "a") == 0.0
      end

      test "returns 0.0 for different single characters" do
        assert :elixir_utils.jaro_similarity("a", "b") == 0.0
      end

      test "returns 0.0 for completely transposed two-character string" do
        assert :elixir_utils.jaro_similarity("ab", "ba") == 0.0
      end

      test "returns similarity score with partial transposition" do
        assert :elixir_utils.jaro_similarity("abcd", "abdc") == 0.9166666666666666
      end

      test "handles slight deviations" do
        assert :elixir_utils.jaro_similarity("martha", "marhta") == 0.9444444444444445
        assert :elixir_utils.jaro_similarity("dwayne", "duane") == 0.8222222222222223
        assert :elixir_utils.jaro_similarity("dixon", "dicksonx") == 0.7666666666666666
      end

      test "is case sensitive" do
        assert :elixir_utils.jaro_similarity("Hello", "hello") == 0.8666666666666667
      end

      test "handles unicode characters" do
        assert :elixir_utils.jaro_similarity("café", "cafe") == 0.8333333333333334
      end

      test "handles emoji characters" do
        assert :elixir_utils.jaro_similarity("hello😀", "hello😀") == 1.0
      end

      test "works with strings, charlists, and integer lists producing same results" do
        str_result = :elixir_utils.jaro_similarity("abc", "abd")
        char_result = :elixir_utils.jaro_similarity(~c"abc", ~c"abd")
        int_result = :elixir_utils.jaro_similarity([97, 98, 99], [97, 98, 100])

        assert str_result == char_result
        assert char_result == int_result
      end

      test "handles lists with string elements" do
        assert :elixir_utils.jaro_similarity(["a", "b", "c"], ["a", "b", "c"]) == 1.0
      end

      test "handles lists with mixed integers and strings" do
        assert :elixir_utils.jaro_similarity([97, "b", 99], [97, "b", 99]) == 1.0
      end

      test "handles lists with multi-character strings" do
        assert :elixir_utils.jaro_similarity(["ab", "cd"], ["ab", "cd"]) == 1.0
      end

      test "handles nested lists" do
        assert :elixir_utils.jaro_similarity([97, 98, [99]], [97, 98, [99]]) == 1.0
      end

      # Error case tests
      # - Top-level invalid argument raises :unicode_util.cp/1 error
      # - Single-element list with invalid type raises :unicode_util.cp/1 error
      # - Multi-element list with invalid type raises :unicode_util.cpl/2 error (with remaining elements)

      test "raises FunctionClauseError when first argument is not bitstring or list" do
        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cp/1", [123]),
                     fn ->
                       :elixir_utils.jaro_similarity(123, "hello")
                     end
      end

      test "raises FunctionClauseError when second argument is not bitstring or list" do
        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cp/1", [123]),
                     fn ->
                       :elixir_utils.jaro_similarity("hello", 123)
                     end
      end

      test "raises FunctionClauseError when first argument is non-binary bitstring" do
        arg = <<1::1, 0::1, 1::1>>

        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cp/1", [arg]),
                     fn -> :elixir_utils.jaro_similarity(arg, "hello") end
      end

      test "raises FunctionClauseError when second argument is non-binary bitstring" do
        arg = <<1::1, 0::1, 1::1>>

        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cp/1", [arg]),
                     fn -> :elixir_utils.jaro_similarity("hello", arg) end
      end

      test "raises FunctionClauseError when first argument is single-element list with invalid element" do
        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cp/1", [%{}]),
                     fn ->
                       :elixir_utils.jaro_similarity([%{}], "hello")
                     end
      end

      test "raises FunctionClauseError when second argument is single-element list with invalid element" do
        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cp/1", [%{}]),
                     fn ->
                       :elixir_utils.jaro_similarity("hello", [%{}])
                     end
      end

      test "raises FunctionClauseError when first argument is multi-element list with invalid element" do
        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cpl/2", [:a, [:b]]),
                     fn ->
                       :elixir_utils.jaro_similarity([:a, :b], "hello")
                     end
      end

      test "raises FunctionClauseError when second argument is multi-element list with invalid element" do
        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cpl/2", [:a, [:b]]),
                     fn ->
                       :elixir_utils.jaro_similarity("hello", [:a, :b])
                     end
      end

      test "raises ArgumentError for invalid UTF-8 bytes" do
        assert_error ArgumentError,
                     "argument error: <<255, 254, 253>>",
                     fn ->
                       :elixir_utils.jaro_similarity(<<255, 254, 253>>, "test")
                     end
      end
    end
  end
end
