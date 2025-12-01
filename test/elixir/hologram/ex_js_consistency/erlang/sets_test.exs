defmodule Hologram.ExJsConsistency.Erlang.SetsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/sets.test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "subtract/2" do
    test "removes elements in the second set from the first set" do
      set1 = :sets.from_list([1, 2, 3])
      set2 = :sets.from_list([2])

      result = :sets.subtract(set1, set2)

      assert result
             |> :sets.to_list()
             |> Enum.sort() == [1, 3]
    end

    test "returns a new set without modifying the original sets" do
      set1 = :sets.from_list([1, 2])
      set2 = :sets.from_list([2])

      result = :sets.subtract(set1, set2)

      # Original sets should remain unchanged
      assert set1
             |> :sets.to_list()
             |> Enum.sort() == [1, 2]

      assert set2
             |> :sets.to_list()
             |> Enum.sort() == [2]

      # Result should be different
      assert result
             |> :sets.to_list()
             |> Enum.sort() == [1]
    end

    test "returns empty set when both sets are the same" do
      set1 = :sets.from_list([1, 2])
      set2 = :sets.from_list([1, 2])

      result = :sets.subtract(set1, set2)

      assert :sets.size(result) == 0
    end

    test "returns the first set when the second set is empty" do
      set1 = :sets.from_list([1, 2])
      set2 = :sets.new()

      result = :sets.subtract(set1, set2)

      assert result
             |> :sets.to_list()
             |> Enum.sort() == [1, 2]

      assert :sets.size(result) == 2
    end

    test "returns empty set when the first set is empty" do
      set1 = :sets.new()
      set2 = :sets.from_list([1])

      result = :sets.subtract(set1, set2)

      assert :sets.size(result) == 0
    end
  end

  describe "union/2" do
    test "combines elements from both sets" do
      set1 = :sets.from_list([1, 2])
      set2 = :sets.from_list([3, 4])

      result = :sets.union(set1, set2)

      assert result
             |> :sets.to_list()
             |> Enum.sort() == [1, 2, 3, 4]
    end

    test "handles overlapping elements correctly (no duplicates)" do
      set1 = :sets.from_list([1, 2, 3])
      set2 = :sets.from_list([2, 3, 4])

      result = :sets.union(set1, set2)

      assert result
             |> :sets.to_list()
             |> Enum.sort() == [1, 2, 3, 4]
    end

    test "returns a new set without modifying the original sets" do
      set1 = :sets.from_list([1])
      set2 = :sets.from_list([2])

      result = :sets.union(set1, set2)

      # Original sets should remain unchanged
      assert set1
             |> :sets.to_list()
             |> Enum.sort() == [1]

      assert set2
             |> :sets.to_list()
             |> Enum.sort() == [2]

      # Result should contain both
      assert result
             |> :sets.to_list()
             |> Enum.sort() == [1, 2]
    end

    test "returns copy of first set when second set is empty" do
      set1 = :sets.from_list([1, 2])
      set2 = :sets.new()

      result = :sets.union(set1, set2)

      assert result
             |> :sets.to_list()
             |> Enum.sort() == [1, 2]
    end

    test "returns copy of second set when first set is empty" do
      set1 = :sets.new()
      set2 = :sets.from_list([1, 2])

      result = :sets.union(set1, set2)

      assert result
             |> :sets.to_list()
             |> Enum.sort() == [1, 2]
    end

    test "returns empty set when both sets are empty" do
      set1 = :sets.new()
      set2 = :sets.new()

      result = :sets.union(set1, set2)

      assert :sets.size(result) == 0
    end

    test "returns same elements when sets are identical" do
      set1 = :sets.from_list([1, 2])
      set2 = :sets.from_list([1, 2])

      result = :sets.union(set1, set2)

      assert result
             |> :sets.to_list()
             |> Enum.sort() == [1, 2]
    end
  end
end
