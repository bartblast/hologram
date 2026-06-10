defmodule Hologram.ExJsConsistency.ComprehensionTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/interpreter_test.mjs
  (comprehension() and comprehensionReduce() sections)
  and a related feature test in test/features/test/control_flow/comprehension_test.exs.
  Always update all three together.

  The mirroring is not complete yet - this file covers only the dependent-generator,
  position-sensitive-filter, and reducer tests. See the TODO below for the remaining
  JavaScript tests that still need Elixir mirrors.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  # TODO: mirror the remaining behavioral tests from the comprehension() section
  # of test/javascript/interpreter_test.mjs:
  # - generator: generates combinations of enumerables items
  # - generator: ignores enumerable items that don't match the pattern
  # - guards: single guard
  # - guards: multiple guards
  # - guards: can access variables from comprehension outer scope
  # - guards: can access variables pattern matched in preceding guards
  # - guards: errors raised inside generators are not caught
  # - filters: remove combinations that don't fullfill specified conditions
  # - filters: can access variables from comprehension outer scope
  # - unique: non-unique items are removed if 'uniq' option is set to true
  # - mapper: can access variables from comprehension outer scope
  # - mapper: uses Enum.into/2 to insert the comprehension result into a collectable

  describe "generator" do
    test "can use variables bound by an earlier generator" do
      result = for x <- [1, 2], y <- [x, x + 10], do: {x, y}

      assert result == [{1, 1}, {1, 11}, {2, 2}, {2, 12}]
    end
  end

  describe "filters" do
    test "placed between generators prunes the branch before the next generator runs" do
      result = for x <- [[1, 2], :nope, [3]], is_list(x), y <- x, do: y

      assert result == [1, 2, 3]
    end
  end

  describe "reducer" do
    test "accumulates over a single generator" do
      result =
        for x <- [1, 2, 3], reduce: 0 do
          acc -> acc + x
        end

      assert result == 6
    end

    test "accumulates over multiple generators" do
      result =
        for x <- [1, 2], y <- [10, 20], reduce: 0 do
          acc -> acc + x * y
        end

      assert result == 90
    end

    test "returns the initial value when the generator is empty" do
      result =
        for x <- [], reduce: 0 do
          acc -> acc + x
        end

      assert result == 0
    end

    test "returns the initial value when filters reject all items" do
      result =
        for x <- [1, 2], x > 10, reduce: 0 do
          acc -> acc + x
        end

      assert result == 0
    end

    test "filters limit which items update the accumulator" do
      result =
        for x <- [1, 2, 3, 4], rem(x, 2) == 0, reduce: 0 do
          acc -> acc + x
        end

      assert result == 6
    end

    test "dispatches to the clause matching the accumulator" do
      result =
        for x <- [1, 2, 3], reduce: 0 do
          0 -> x
          acc -> acc * 10 + x
        end

      assert result == 123
    end

    test "dispatches to the clause whose guards pass" do
      result =
        for x <- [1, 2, 3], reduce: 0 do
          acc when acc <= 1 -> acc + x
          acc -> acc + x * 10
        end

      assert result == 33
    end

    test "reducer clauses can access variables from comprehension outer scope" do
      a = 1

      result =
        for x <- [10, 20], reduce: 0 do
          acc -> acc + x + a
        end

      assert result == 32
    end

    test "raises CaseClauseError when no clause matches the accumulator" do
      assert_error CaseClauseError, build_case_clause_error_msg(0), fn ->
        for x <- [1], reduce: 0 do
          :nomatch -> x
        end
      end
    end
  end
end
