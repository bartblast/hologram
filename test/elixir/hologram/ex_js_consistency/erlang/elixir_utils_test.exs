defmodule Elixir.Hologram.ExJsConsistency.Erlang.ElixirUtilsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/elixir_utils_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  if Version.match?(System.version(), "> 1.17.0") do
    describe "jaro_similarity/2" do
      test "works with strings, charlists, and integer lists producing same results" do
        str_result = :elixir_utils.jaro_similarity("abc", "abd")
        char_result = :elixir_utils.jaro_similarity(~c"abc", ~c"abd")
        int_result = :elixir_utils.jaro_similarity([97, 98, 99], [97, 98, 100])
        assert str_result == char_result
        assert char_result == int_result
      end

      test "handles slight deviations" do
        assert_in_delta :elixir_utils.jaro_similarity("martha", "marhta"), 0.944, 0.001
        assert_in_delta :elixir_utils.jaro_similarity("dwayne", "duane"), 0.822, 0.001
        assert_in_delta :elixir_utils.jaro_similarity("dixon", "dicksonx"), 0.767, 0.001
      end

      test "returns 0.0 for completely different inputs" do
        assert :elixir_utils.jaro_similarity("abc", "xyz") == 0.0
      end

      test "handles empty inputs" do
        assert :elixir_utils.jaro_similarity("", "") == 1.0
        assert :elixir_utils.jaro_similarity("", "hello") == 0.0
        assert :elixir_utils.jaro_similarity("hello", "") == 0.0
      end

      test "handles single character inputs" do
        # Known issue in :elixir_utils.jaro_similarity/2
        # will be fixed when Elixir requires Erlang/OTP 27+
        # and switches to :string.jaro_similarity/2
        assert :elixir_utils.jaro_similarity("a", "a") == 0.0
        assert :elixir_utils.jaro_similarity("a", "b") == 0.0
      end

      test "handles transpositions" do
        assert :elixir_utils.jaro_similarity("ab", "ba") == 0.0
        assert :elixir_utils.jaro_similarity("abcd", "abdc") > 0.9
      end

      test "is case sensitive" do
        assert :elixir_utils.jaro_similarity("Hello", "hello") < 1.0
      end

      test "handles unicode characters" do
        assert :elixir_utils.jaro_similarity("café", "cafe") < 1.0
      end

      test "handles lists with string elements" do
        assert :elixir_utils.jaro_similarity(["a", "b", "c"], ["a", "b", "c"]) == 1.0
      end

      test "handles lists with mixed integers and strings" do
        assert :elixir_utils.jaro_similarity([97, "b", 99], [97, "b", 99]) == 1.0
      end

      test "handles lists with multi-character strings" do
        result = :elixir_utils.jaro_similarity(["ab", "cd"], ["ab", "cd"])
        assert result == 1
      end

      test "handles nested lists" do
        result = :elixir_utils.jaro_similarity([1, 2, [1]], [1, 2, [1]])
        assert result == 1.0
      end

      # Error handling tests
      # - Top-level invalid argument raises :unicode_util.cp/1 error
      # - Single-element list with invalid type raises :unicode_util.cp/1 error
      # - Multi-element list with invalid type raises :unicode_util.cpl/2 error (with remaining elements)

      test "raises FunctionClauseError for invalid arguments" do
        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cp/1", [123]),
                     fn ->
                       :elixir_utils.jaro_similarity(123, "hello")
                     end
      end

      test "raises FunctionClauseError for single-element list with invalid type" do
        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cp/1", [%{}]),
                     fn ->
                       :elixir_utils.jaro_similarity([%{}], [%{}])
                     end
      end

      test "raises FunctionClauseError for multi-element list with invalid type" do
        assert_error FunctionClauseError,
                     build_function_clause_error_msg(":unicode_util.cpl/2", [:a, [:b]]),
                     fn ->
                       :elixir_utils.jaro_similarity([:a, :b], [:a, :b])
                     end
      end
    end
  end
end
