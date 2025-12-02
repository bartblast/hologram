defmodule Hologram.ExJsConsistency.Erlang.SetsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/sets_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "to_list/1" do
    test "returns an empty list if given an empty set" do
      result =
        []
        |> :sets.from_list()
        |> :sets.to_list()

      assert result == []
    end

    test "returns a list of values if given a non-empty set" do
      sorted_result =
        [1, 1, "1", false]
        |> :sets.from_list()
        |> :sets.to_list()
        |> Enum.sort()

      assert sorted_result == [1, false, "1"]
    end

    test "raises FunctionClauseError if the argument is not a set" do
      expected_msg = build_function_clause_error_msg(":sets.to_list/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :sets.to_list(:abc)
      end
    end
  end
end
