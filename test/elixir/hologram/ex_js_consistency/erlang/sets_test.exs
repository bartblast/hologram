defmodule Hologram.ExJsConsistency.Erlang.SetsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/sets_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "add_element/2" do
    test "adds a new element to the set" do
      set = :sets.from_list([1, 3], [{:version, 2}])

      result = :sets.add_element(2, set)
      expected = :sets.from_list([1, 2, 3], [{:version, 2}])

      assert result == expected
    end

    test "returns the same set if element is already present" do
      set = :sets.from_list([1, 2, 3], [{:version, 2}])

      result = :sets.add_element(2, set)
      expected = :sets.from_list([1, 2, 3], [{:version, 2}])

      assert result == expected
    end

    test "adds element to empty set" do
      set = :sets.from_list([], [{:version, 2}])

      result = :sets.add_element(1, set)
      expected = :sets.from_list([1], [{:version, 2}])

      assert result == expected
    end

    test "uses strict matching (integer vs float)" do
      set = :sets.from_list([1.0], [{:version, 2}])

      result = :sets.add_element(1, set)
      expected = :sets.from_list([1, 1.0], [{:version, 2}])

      assert result == expected
    end

    test "doesn't mutate the original set" do
      set = :sets.from_list([1, 2], [{:version, 2}])

      :sets.add_element(3, set)

      expected = :sets.from_list([1, 2], [{:version, 2}])

      assert set == expected
    end

    test "raises FunctionClauseError if argument is not a set" do
      expected_msg = build_function_clause_error_msg(":sets.add_element/2", [:elem, :not_a_set])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.add_element(:elem, :not_a_set)
      end
    end
  end

  describe "del_element/2" do
    test "removes an existing element from the set" do
      set = :sets.from_list([1, 2, 3], [{:version, 2}])
      result = :sets.del_element(2, set)
      expected = :sets.from_list([1, 3], [{:version, 2}])

      assert result == expected
    end

    test "returns the same set if element is not present" do
      set = :sets.from_list([1, 2, 3], [{:version, 2}])
      result = :sets.del_element(42, set)

      assert result == set
    end

    test "returns empty set when removing from empty set" do
      set = :sets.from_list([], [{:version, 2}])
      result = :sets.del_element(:any, set)

      assert result == set
    end

    test "uses strict matching (integer vs float)" do
      set = :sets.from_list([2], [{:version, 2}])

      assert :sets.del_element(2.0, set) == set
    end

    test "raises FunctionClauseError if argument is not a set" do
      expected_msg = build_function_clause_error_msg(":sets.del_element/2", [:elem, :not_a_set])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.del_element(:elem, :not_a_set)
      end
    end
  end

  describe "filter/2" do
    setup do
      [
        set: :sets.from_list([1, 2, 3], version: 2),
        fun: fn elem -> elem > 2 end
      ]
    end

    test "filters elements from a non-empty set", %{set: set, fun: fun} do
      result = :sets.filter(fun, set)

      assert result == :sets.from_list([3], version: 2)
    end

    test "returns an empty set if the predicate filters out all elements", %{set: set} do
      result = :sets.filter(fn elem -> elem > 10 end, set)

      assert result == :sets.from_list([], version: 2)
    end

    test "returns the same set if the predicate matches all elements", %{set: set} do
      result = :sets.filter(fn elem -> elem > 0 end, set)

      assert result == set
    end

    test "filters elements from an empty set", %{fun: fun} do
      set = :sets.new(version: 2)
      result = :sets.filter(fun, set)

      assert result == :sets.from_list([], version: 2)
    end

    test "raises FunctionClauseError if the first argument is not an anonymous function", %{
      set: set
    } do
      expected_msg = build_function_clause_error_msg(":sets.filter/2", [:invalid, set])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.filter(:invalid, set)
      end
    end

    test "raises FunctionClauseError if the first argument is an anonymous function with wrong arity",
         %{set: set} do
      wrong_arity_fun = fn x, y -> x == y end
      expected_msg = build_function_clause_error_msg(":sets.filter/2", [wrong_arity_fun, set])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.filter(wrong_arity_fun, set)
      end
    end

    test "raises FunctionClauseError if the second argument is not a set", %{fun: fun} do
      expected_msg = build_function_clause_error_msg(":sets.filter/2", [fun, :abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.filter(fun, :abc)
      end
    end

    test "raises ErlangError if the predicate does not return a boolean", %{set: set} do
      assert_error ErlangError, build_erlang_error_msg("{:bad_filter, :not_a_boolean}"), fn ->
        :sets.filter(fn _elem -> :not_a_boolean end, set)
      end
    end
  end

  describe "fold/3" do
    setup do
      [opts: [{:version, 2}]]
    end

    test "folds over an empty set and returns the initial accumulator", %{opts: opts} do
      set = :sets.new(opts)
      fun = fn _elem, acc -> acc end
      result = :sets.fold(fun, 1, set)

      assert result == 1
    end

    test "folds over a set with a single element", %{opts: opts} do
      set = :sets.from_list([2], opts)
      fun = fn elem, acc -> [elem | acc] end
      result = :sets.fold(fun, [], set)

      assert result == [2]
    end

    test "folds over a set with multiple elements", %{opts: opts} do
      set = :sets.from_list([1, 2, 3], opts)
      fun = fn elem, acc -> acc + elem end
      result = :sets.fold(fun, 0, set)

      assert result == 6
    end

    test "raises FunctionClauseError if the first argument is not a function", %{opts: opts} do
      set = :sets.from_list([1, 2, 3], opts)
      expected_msg = build_function_clause_error_msg(":sets.fold/3", [:abc, 0, set])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.fold(:abc, 0, set)
      end
    end

    test "raises FunctionClauseError if the function has wrong arity", %{opts: opts} do
      set = :sets.from_list([1, 2, 3], opts)
      fun = fn elem -> elem end
      expected_msg = build_function_clause_error_msg(":sets.fold/3", [fun, 0, set])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.fold(fun, 0, set)
      end
    end

    test "raises FunctionClauseError if the third argument is not a set" do
      fun = fn _elem, acc -> acc end
      expected_msg = build_function_clause_error_msg(":sets.fold/3", [fun, 0, :abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.fold(fun, 0, :abc)
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

  describe "intersection/2" do
    setup do
      [
        empty_set: :sets.new(version: 2),
        set_123: :sets.from_list([1, 2, 3], version: 2)
      ]
    end

    test "returns the intersection of two sets with common elements", %{set_123: set_123} do
      set_234 = :sets.from_list([2, 3, 4], version: 2)

      result = :sets.intersection(set_123, set_234)
      expected = :sets.from_list([2, 3], version: 2)

      assert result == expected
    end

    test "returns an empty set if sets have no common elements" do
      set_12 = :sets.from_list([1, 2], version: 2)
      set_3 = :sets.from_list([3], version: 2)

      assert :sets.intersection(set_12, set_3) == :sets.new(version: 2)
    end

    test "returns an empty set if both sets are empty", %{empty_set: empty_set} do
      assert :sets.intersection(empty_set, empty_set) == empty_set
    end

    test "returns an empty set if first set is empty", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.intersection(empty_set, set_123) == empty_set
    end

    test "returns an empty set if second set is empty", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.intersection(set_123, empty_set) == empty_set
    end

    test "returns the same set if sets are identical", %{set_123: set_123} do
      assert :sets.intersection(set_123, set_123) == set_123
    end

    test "uses strict matching (integer vs float)" do
      set_int = :sets.from_list([1], version: 2)
      set_float = :sets.from_list([1.0], version: 2)

      assert :sets.intersection(set_int, set_float) == :sets.new(version: 2)
    end

    test "raises FunctionClauseError if the first argument is not a set", %{set_123: set_123} do
      expected_msg = build_function_clause_error_msg(":sets.size/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.intersection(:abc, set_123)
      end
    end

    test "raises FunctionClauseError if the second argument is not a set", %{set_123: set_123} do
      expected_msg = build_function_clause_error_msg(":sets.size/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.intersection(set_123, :abc)
      end
    end
  end

  describe "is_disjoint/2" do
    setup do
      [
        empty_set: :sets.new(version: 2),
        set_123: :sets.from_list([1, 2, 3], version: 2)
      ]
    end

    test "returns true if sets have no common elements" do
      set1 = :sets.from_list([1, 2], version: 2)
      set2 = :sets.from_list([3], version: 2)

      assert :sets.is_disjoint(set1, set2) == true
    end

    test "returns false if sets have common elements" do
      set1 = :sets.from_list([1, 2], version: 2)
      set2 = :sets.from_list([2, 3], version: 2)

      assert :sets.is_disjoint(set1, set2) == false
    end

    test "returns true if both sets are empty", %{empty_set: empty_set} do
      assert :sets.is_disjoint(empty_set, empty_set) == true
    end

    test "returns true if first set is empty", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.is_disjoint(empty_set, set_123) == true
    end

    test "returns true if second set is empty", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.is_disjoint(set_123, empty_set) == true
    end

    test "returns false if sets are identical", %{set_123: set_123} do
      assert :sets.is_disjoint(set_123, set_123) == false
    end

    test "uses strict matching (integer vs float)" do
      set_int = :sets.from_list([1], version: 2)
      set_float = :sets.from_list([1.0], version: 2)

      assert :sets.is_disjoint(set_int, set_float) == true
    end

    test "raises FunctionClauseError if the first argument is not a set", %{set_123: set_123} do
      expected_msg = build_function_clause_error_msg(":sets.size/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.is_disjoint(:abc, set_123)
      end
    end

    test "raises FunctionClauseError if the second argument is not a set", %{set_123: set_123} do
      expected_msg = build_function_clause_error_msg(":sets.size/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.is_disjoint(set_123, :abc)
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

  describe "is_subset/2" do
    setup do
      empty_set = :sets.new(version: 2)
      set_123 = :sets.from_list([1, 2, 3], version: 2)

      [empty_set: empty_set, set_123: set_123]
    end

    test "returns true if all elements in first set are in second set", %{set_123: set_123} do
      set_12 = :sets.from_list([1, 2], version: 2)

      assert :sets.is_subset(set_12, set_123) == true
    end

    test "returns true if both sets are the same", %{set_123: set_123} do
      assert :sets.is_subset(set_123, set_123) == true
    end

    test "returns true if both sets are empty", %{empty_set: empty_set} do
      assert :sets.is_subset(empty_set, empty_set) == true
    end

    test "returns true if first set is empty and second set isn't", %{
      empty_set: empty_set,
      set_123: set_123
    } do
      assert :sets.is_subset(empty_set, set_123) == true
    end

    test "returns false if not all elements in first set are in second set", %{set_123: set_123} do
      set_14 = :sets.from_list([1, 4], version: 2)

      assert :sets.is_subset(set_14, set_123) == false
    end

    test "uses strict matching (integer vs float)" do
      first_set = :sets.from_list([1], version: 2)
      second_set = :sets.from_list([1.0], version: 2)

      assert :sets.is_subset(first_set, second_set) == false
    end

    test "raises FunctionClauseError if the first argument is not a set", %{set_123: set_123} do
      expected_msg = ~r"""
      no function clause matching in :sets\.fold/3

      The following arguments were given to :sets\.fold/3:

          # 1
          #Function<[0-9]+\.[0-9]+/2 in :sets\.is_subset/2>

          # 2
          true

          # 3
          :abc
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.is_subset(:abc, set_123)
      end
    end

    test "raises FunctionClauseError if the second argument is not a set", %{set_123: set_123} do
      expected_msg = build_function_clause_error_msg(":sets.is_element/2", [1, :abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.is_subset(set_123, :abc)
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

  describe "size/1" do
    test "returns zero if given an empty set" do
      set = :sets.new(version: 2)

      assert :sets.size(set) == 0
    end

    test "returns count for non-empty set" do
      set = :sets.from_list([1, 2, 3], version: 2)

      assert :sets.size(set) == 3
    end

    test "raises FunctionClauseError if the argument is not a set" do
      expected_msg = build_function_clause_error_msg(":sets.size/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.size(:abc)
      end
    end
  end

  describe "subtract/2" do
    setup do
      [
        empty_set: :sets.new(version: 2),
        set_123: :sets.from_list([1, 2, 3], version: 2)
      ]
    end

    test "returns elements in the first set that are not in the second set", %{set_123: set_123} do
      set_234 = :sets.from_list([2, 3, 4], version: 2)

      result = :sets.subtract(set_123, set_234)
      expected = :sets.from_list([1], version: 2)

      assert result == expected
    end

    test "returns the first set if sets have no common elements" do
      set_12 = :sets.from_list([1, 2], version: 2)
      set_3 = :sets.from_list([3], version: 2)

      assert :sets.subtract(set_12, set_3) == set_12
    end

    test "returns an empty set if both sets are empty", %{empty_set: empty_set} do
      assert :sets.subtract(empty_set, empty_set) == empty_set
    end

    test "returns an empty set if first set is empty", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.subtract(empty_set, set_123) == empty_set
    end

    test "returns the first set if second set is empty", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.subtract(set_123, empty_set) == set_123
    end

    test "returns an empty set if sets are identical", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.subtract(set_123, set_123) == empty_set
    end

    test "uses strict matching (integer vs float)" do
      set_int = :sets.from_list([1], version: 2)
      set_float = :sets.from_list([1.0], version: 2)

      assert :sets.subtract(set_int, set_float) == set_int
    end

    test "raises FunctionClauseError if the first argument is not a set", %{set_123: set_123} do
      expected_msg = ~r"""
      no function clause matching in :sets\.filter/2

      The following arguments were given to :sets\.filter/2:

          # 1
          #Function<[0-9]+\.[0-9]+/1 in :sets\.subtract/2>

          # 2
          :abc
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.subtract(:abc, set_123)
      end
    end

    test "raises FunctionClauseError if the second argument is not a set", %{set_123: set_123} do
      expected_msg = build_function_clause_error_msg(":sets.is_element/2", [1, :abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.subtract(set_123, :abc)
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

  describe "union/2" do
    setup do
      [
        empty_set: :sets.new(version: 2),
        set_123: :sets.from_list([1, 2, 3], version: 2)
      ]
    end

    test "returns the union of two sets with some common elements", %{set_123: set_123} do
      set_234 = :sets.from_list([2, 3, 4], version: 2)

      result = :sets.union(set_123, set_234)
      expected = :sets.from_list([1, 2, 3, 4], version: 2)

      assert result == expected
    end

    test "returns the combined set if sets have no common elements" do
      set_12 = :sets.from_list([1, 2], version: 2)
      set_3 = :sets.from_list([3], version: 2)

      assert :sets.union(set_12, set_3) == :sets.from_list([1, 2, 3], version: 2)
    end

    test "returns an empty set if both sets are empty", %{empty_set: empty_set} do
      assert :sets.union(empty_set, empty_set) == empty_set
    end

    test "returns the second set if first set is empty", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.union(empty_set, set_123) == set_123
    end

    test "returns the first set if second set is empty", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.union(set_123, empty_set) == set_123
    end

    test "returns the same set if sets are identical", %{set_123: set_123} do
      assert :sets.union(set_123, set_123) == set_123
    end

    test "uses strict matching (integer vs float)" do
      set_int = :sets.from_list([1], version: 2)
      set_float = :sets.from_list([1.0], version: 2)

      assert :sets.union(set_int, set_float) == :sets.from_list([1, 1.0], version: 2)
    end

    test "raises FunctionClauseError if the first argument is not a set", %{set_123: set_123} do
      expected_msg = build_function_clause_error_msg(":sets.size/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.union(:abc, set_123)
      end
    end

    test "raises FunctionClauseError if the second argument is not a set", %{set_123: set_123} do
      expected_msg = build_function_clause_error_msg(":sets.size/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.union(set_123, :abc)
      end
    end
  end
end
