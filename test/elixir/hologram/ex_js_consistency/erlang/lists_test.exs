defmodule Hologram.ExJsConsistency.Erlang.ListsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/lists_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  describe "flatten/1" do
    test "works with empty list" do
      assert :lists.flatten([]) == []
    end

    test "works with non-nested list" do
      assert :lists.flatten([1, 2, 3]) == [1, 2, 3]
    end

    test "works with nested list" do
      assert :lists.flatten([1, [2, [3, 4, 5], 6], 7]) == [1, 2, 3, 4, 5, 6, 7]
    end

    test "raises FunctionClauseError if the argument is not a list" do
      assert_raise FunctionClauseError, "no function clause matching in :lists.flatten/1", fn ->
        :lists.flatten(:abc)
      end
    end
  end

  describe "foldl/3" do
    setup do
      [fun: fn value, acc -> acc + value end]
    end

    test "reduces empty list", %{fun: fun} do
      assert :lists.foldl(fun, 0, []) == 0
    end

    test "reduces non-empty list", %{fun: fun} do
      assert :lists.foldl(fun, 0, [1, 2, 3]) == 6
    end

    test "raises FunctionClauseError if the first argument is not an anonymous function" do
      assert_raise FunctionClauseError, "no function clause matching in :lists.foldl/3", fn ->
        :lists.foldl(:abc, 0, [])
      end
    end

    test "raises FunctionClauseError if the first argument is an anonymous function with arity different than 2" do
      assert_raise FunctionClauseError, "no function clause matching in :lists.foldl/3", fn ->
        :lists.foldl(fn x -> x end, 0, [])
      end
    end

    test "raises CaseClauseError if the third argument is not a list", %{fun: fun} do
      assert_raise CaseClauseError, "no case clause matching: :abc", fn ->
        :lists.foldl(fun, 0, :abc)
      end
    end
  end

  describe "reverse/1" do
    test "returns a list with the elements in the argument in reverse order" do
      assert :lists.reverse([1, 2, 3]) == [3, 2, 1]
    end

    test "raises FunctionClauseError if the argument is not a list" do
      assert_raise FunctionClauseError, "no function clause matching in :lists.reverse/1", fn ->
        :lists.reverse(:abc)
      end
    end
  end
end
