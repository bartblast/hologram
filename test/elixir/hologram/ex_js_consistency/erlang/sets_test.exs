defmodule Hologram.ExJsConsistency.Erlang.SetsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/sets_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

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

  describe "is_subset/2" do
    setup do
      empty_set = :sets.new(version: 2)
      set_123 = :sets.from_list([1, 2, 3], version: 2)

      [empty_set: empty_set, set_123: set_123]
    end

    test "returns true if set1 is an empty set", %{empty_set: empty_set} do
      assert :sets.is_subset(empty_set, empty_set)
    end

    test "returns true if set1 is empty and set2 isn't", %{empty_set: empty_set, set_123: set_123} do
      assert :sets.is_subset(empty_set, set_123)
    end

    test "returns false if not all elements in set1 are in set2", %{empty_set: empty_set} do
      set1 = :sets.from_list([1], version: 2)
      refute :sets.is_subset(set1, empty_set)
    end

    test "returns true if both sets are the same" do
      set1 = :sets.from_list([1, 2], version: 2)
      set2 = :sets.from_list([1, 2], version: 2)
      assert :sets.is_subset(set1, set2)
    end

    test "returns true if all elements in set1 are in set2" do
      set1 = :sets.from_list([1], version: 2)
      set2 = :sets.from_list([1, 2], version: 2)
      assert :sets.is_subset(set1, set2)
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
      expected_msg = ~r"""
      no function clause matching in :sets\.is_element/2

      The following arguments were given to :sets\.is_element/2:

          # 1
          1

          # 2
          :abc
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.is_subset(set_123, :abc)
      end
    end
  end
end
