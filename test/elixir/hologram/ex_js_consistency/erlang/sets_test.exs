defmodule Hologram.ExJsConsistency.Erlang.SetsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/sets_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "from_list/2" do
    test "creates a set from an empty list with version 2 option" do
      result = :sets.from_list([], [{:version, 2}])
      assert result == %{}
    end

    test "creates a set from a list with elements and version 2 option" do
      result = :sets.from_list([1, 2, 3], [{:version, 2}])
      assert result == %{1 => [], 2 => [], 3 => []}
    end

    test "creates a set from a list with duplicate elements" do
      result = :sets.from_list([1, 2, 1, 3], [{:version, 2}])
      assert result == %{1 => [], 2 => [], 3 => []}
    end

    test "raises ArgumentError when list is not a list" do
      assert_raise ArgumentError, fn ->
        :sets.from_list(:invalid, [{:version, 2}])
      end
    end

    test "raises ArgumentError when list is an improper list" do
      assert_raise ArgumentError, fn ->
        :sets.from_list([1 | 2], [{:version, 2}])
      end
    end
  end

  describe "new/1" do
    test "creates a new empty set with version 2 option" do
      result = :sets.new([{:version, 2}])
      assert result == %{}
    end

    test "ignores invalid option keys (doesn't raise)" do
      :sets.new([{:invalid, 2}])
    end

    test "raises CaseClauseError when version is invalid" do
      assert_raise CaseClauseError, fn ->
        :sets.new([{:version, 3}])
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
