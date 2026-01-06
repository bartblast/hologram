defmodule Hologram.ExJsConsistency.Erlang.SetsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/sets_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "filter/2" do
    setup do
      [set: :sets.from_list([1, 2, 3], version: 2)]
    end

    test "filters elements from a non-empty set", %{set: set} do
      result = :sets.filter(fn x -> x > 2 end, set)

      assert result == :sets.from_list([3], version: 2)
    end

    test "returns an empty set if the predicate filters out all elements", %{set: set} do
      result = :sets.filter(fn x -> x > 10 end, set)

      assert result == :sets.from_list([], version: 2)
    end

    test "returns the same set if the predicate matches all elements", %{set: set} do
      result = :sets.filter(fn x -> x > 0 end, set)

      assert result == set
    end

    test "filters elements from an empty set" do
      set = :sets.new(version: 2)
      result = :sets.filter(fn x -> x > 0 end, set)

      assert result == :sets.from_list([], version: 2)
    end

    test "raises FunctionClauseError if the first argument is not an anonymous function" do
      set = :sets.from_list([1, 2, 3], version: 2)

      expected_msg = build_function_clause_error_msg(":sets.filter/2", [:invalid, set])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.filter(:invalid, set)
      end
    end

    test "raises FunctionClauseError if the second argument is not a set" do
      fun = fn x -> x > 0 end

      expected_msg = build_function_clause_error_msg(":sets.filter/2", [fun, :abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.filter(fun, :abc)
      end
    end

    test "raises ErlangError if the predicate does not return a boolean" do
      set = :sets.from_list([1, 2, 3], version: 2)

      assert_error ErlangError, build_erlang_error_msg("{:bad_filter, :not_a_boolean}"), fn ->
        :sets.filter(fn _x -> :not_a_boolean end, set)
      end
    end
  end

  describe "from_list/2" do
    setup do
      [opts: [{:version, 2}]]
    end

    test "creates a set from an empty list", %{opts: opts} do
      assert :sets.from_list([], opts) == %{}
    end

    test "creates a set from a non-empty list", %{opts: opts} do
      result = :sets.from_list([1, 2, 3], opts)
      assert result == %{1 => [], 2 => [], 3 => []}
    end

    test "creates a set from a list with duplicate elements", %{opts: opts} do
      result = :sets.from_list([1, 2, 1, 3], opts)
      assert result == %{1 => [], 2 => [], 3 => []}
    end

    test "ignores invalid options" do
      assert :sets.from_list([], invalid: 1, version: 2) == %{}
    end

    test "raises ArgumentError if the first argument is not a list", %{opts: opts} do
      expected_msg = build_argument_error_msg(1, "not a list")

      assert_error ArgumentError, expected_msg, fn ->
        :sets.from_list(:invalid, opts)
      end
    end

    test "raises ArgumentError if the first argument is an improper list", %{opts: opts} do
      expected_msg = build_argument_error_msg(1, "not a proper list")

      assert_error ArgumentError, expected_msg, fn ->
        :sets.from_list([1 | 2], opts)
      end
    end

    test "raises FunctionClauseError if the second argument is not a list" do
      expected_msg =
        build_function_clause_error_msg(":proplists.get_value/3", [:version, :invalid, 1])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.from_list([], :invalid)
      end
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the second argument is an a improper list" do
      expected_msg = build_function_clause_error_msg(":proplists.get_value/3", [:version, 2, 1])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.from_list([], [1 | 2])
      end
    end

    test "raises CaseClauseError for invalid versions" do
      assert_error CaseClauseError, "no case clause matching: :abc", fn ->
        :sets.from_list([], version: :abc)
      end
    end
  end

  describe "is_element/2" do
    test "returns true if element is in the set" do
      set = :sets.from_list([1, 2, 3], [{:version, 2}])
      assert :sets.is_element(2, set) == true
    end

    test "returns false if element is not in the set" do
      set = :sets.from_list([1, 2, 3], [{:version, 2}])
      assert :sets.is_element(42, set) == false
    end

    test "returns false for empty set" do
      set = :sets.new([{:version, 2}])
      assert :sets.is_element(:any, set) == false
    end

    test "uses strict matching (integer vs float)" do
      set = :sets.from_list([1], [{:version, 2}])
      assert :sets.is_element(1.0, set) == false
    end

    test "raises FunctionClauseError if the second argument is not a set" do
      expected_msg = build_function_clause_error_msg(":sets.is_element/2", [:elem, :not_a_set])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.is_element(:elem, :not_a_set)
      end
    end
  end

  describe "new/1" do
    setup do
      [opts: [{:version, 2}]]
    end

    test "creates a new set", %{opts: opts} do
      assert :sets.new(opts) == %{}
    end

    test "ignores invalid options" do
      assert :sets.new(invalid: 1, version: 2) == %{}
    end

    test "raises FunctionClauseError if the first argument is not a list" do
      expected_msg =
        build_function_clause_error_msg(":proplists.get_value/3", [:version, :invalid, 1])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.new(:invalid)
      end
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the first argument is an a improper list" do
      expected_msg = build_function_clause_error_msg(":proplists.get_value/3", [:version, 2, 1])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.new([1 | 2])
      end
    end

    test "raises CaseClauseError for invalid versions" do
      assert_error CaseClauseError, "no case clause matching: :abc", fn ->
        :sets.new(version: :abc)
      end
    end
  end

  describe "to_list/1" do
    test "returns an empty list if given an empty set" do
      set = :sets.new(version: 2)

      assert :sets.to_list(set) == []
    end

    test "returns a list of values if given a non-empty set" do
      sorted_result =
        [1, 2.0]
        |> :sets.from_list(version: 2)
        |> :sets.to_list()
        |> Enum.sort()

      assert sorted_result == [1, 2.0]
    end

    test "raises FunctionClauseError if the argument is not a set" do
      expected_msg = build_function_clause_error_msg(":sets.to_list/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.to_list(:abc)
      end
    end
  end
end
