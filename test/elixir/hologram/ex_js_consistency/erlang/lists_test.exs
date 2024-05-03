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

    test "raises FunctionClauseError if the argument (or any nested item) is an improper list" do
      assert_raise FunctionClauseError,
                   "no function clause matching in :lists.do_flatten/2",
                   fn ->
                     :lists.flatten([1, 2, [3, 4 | 5], 6, 7])
                   end
    end
  end

  describe "foldl/3" do
    setup do
      [fun: fn elem, acc -> acc + elem end]
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

    test "raises FunctionClauseError if the third argument is an improper list", %{fun: fun} do
      assert_raise FunctionClauseError,
                   "no function clause matching in :lists.foldl_1/3",
                   fn ->
                     :lists.foldl(fun, 0, [1, 2 | 3])
                   end
    end
  end

  describe "keyfind/3" do
    test "returns the tuple that contains the given value at the given one-based index" do
      assert :lists.keyfind(7, 3, [{1, 2}, :abc, {5, 6, 7}]) == {5, 6, 7}
    end

    test "returns false if there is no tuple that fulfills the given conditions" do
      assert :lists.keyfind(7, 3, [:abc]) == false
    end

    test "raises ArgumentError if the second argument (index) is not an integer" do
      assert_raise ArgumentError,
                   build_errors_found_msg(2, "not an integer"),
                   fn ->
                     :lists.keyfind(:abc, :xyz, [])
                   end
    end

    test "raises ArgumentError if the second argument (index) is smaller than 1" do
      assert_raise ArgumentError,
                   build_errors_found_msg(2, "out of range"),
                   fn ->
                     :lists.keyfind(:abc, 0, [])
                   end
    end

    test "raises ArgumentError if the third argument (tuples) is not a list" do
      assert_raise ArgumentError,
                   build_errors_found_msg(3, "not a list"),
                   fn ->
                     :lists.keyfind(:abc, 1, :xyz)
                   end
    end

    test "raises ArgumentError if the third argument (tuples) is an improper list" do
      assert_raise ArgumentError,
                   build_errors_found_msg(3, "not a proper list"),
                   fn ->
                     :lists.keyfind(7, 4, [1, 2 | 3])
                   end
    end
  end

  describe "keymember/3" do
    test "returns true if there is a tuple that fulfills the given conditions" do
      assert :lists.keymember(7, 3, [{1, 2}, :abc, {5, 6, 7}]) == true
    end

    test "returns false if there is no tuple that fulfills the given conditions" do
      assert :lists.keymember(7, 3, [:abc]) == false
    end

    test "raises ArgumentError if the second argument (index) is not an integer" do
      assert_raise ArgumentError,
                   build_errors_found_msg(2, "not an integer"),
                   fn ->
                     :lists.keymember(:abc, :xyz, [])
                   end
    end

    test "raises ArgumentError if the second argument (index) is smaller than 1" do
      assert_raise ArgumentError,
                   build_errors_found_msg(2, "out of range"),
                   fn ->
                     :lists.keymember(:abc, 0, [])
                   end
    end

    test "raises ArgumentError if the third argument (tuples) is not a list" do
      assert_raise ArgumentError,
                   build_errors_found_msg(3, "not a list"),
                   fn ->
                     :lists.keymember(:abc, 1, :xyz)
                   end
    end
  end

  describe "map/2" do
    setup do
      [fun: fn elem -> elem * 10 end]
    end

    test "maps empty list", %{fun: fun} do
      assert :lists.map(fun, []) == []
    end

    test "maps non-empty list", %{fun: fun} do
      assert :lists.map(fun, [1, 2, 3]) == [10, 20, 30]
    end

    test "raises FunctionClauseError if the first argument is not an anonymous function" do
      assert_raise FunctionClauseError, "no function clause matching in :lists.map/2", fn ->
        :lists.map(:abc, [])
      end
    end

    test "raises FunctionClauseError if the first argument is an anonymous function with arity different than 1" do
      assert_raise FunctionClauseError, "no function clause matching in :lists.map/2", fn ->
        :lists.map(fn x, y -> x + y end, [])
      end
    end

    test "raises CaseClauseError if the second argument is not a list", %{fun: fun} do
      assert_raise CaseClauseError, "no case clause matching: :abc", fn ->
        :lists.map(fun, :abc)
      end
    end
  end

  describe "member/2" do
    test "is a member" do
      assert :lists.member(2, [1, 2, 3]) == true
    end

    test "is not a member" do
      assert :lists.member(4, [1, 2, 3]) == false
    end

    test "uses strict equality" do
      assert :lists.member(2, [1, 2.0, 3]) == false
    end

    test "raises ArgumentError if the second argument is not a list" do
      assert_raise ArgumentError,
                   build_errors_found_msg(2, "not a list"),
                   fn ->
                     :lists.member(2, :abc)
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

  describe "reverse/2" do
    test "1st arg = [1, 2], 2nd arg = [3, 4]" do
      assert :lists.reverse([1, 2], [3, 4]) == [2, 1, 3, 4]
    end

    test "1st arg = [1, 2], 2nd arg = [3 | 4]" do
      assert :lists.reverse([1, 2], [3 | 4]) == [2, 1, 3 | 4]
    end

    test "1st arg = [1, 2], 2nd arg = []" do
      assert :lists.reverse([1, 2], []) == [2, 1]
    end

    test "1st arg = [1, 2], 2nd arg = 5" do
      assert :lists.reverse([1, 2], 5) == [2, 1 | 5]
    end

    test "1st arg is an improper list" do
      assert_raise ArgumentError, build_errors_found_msg(1, "not a proper list"), fn ->
        :lists.reverse([1 | 2], [3, 4])
      end
    end

    test "1st arg = [], 2nd arg = [3, 4]" do
      assert :lists.reverse([], [3, 4]) == [3, 4]
    end

    test "1st arg = [], 2nd arg = [3 | 4]" do
      assert :lists.reverse([], [3 | 4]) == [3 | 4]
    end

    test "1st arg = [], 2nd arg = []" do
      assert :lists.reverse([], []) == []
    end

    test "1st arg = [], 2nd arg = 5" do
      assert :lists.reverse([], 5) == 5
    end

    test "1st arg is not a list" do
      assert_raise ArgumentError, build_errors_found_msg(1, "not a list"), fn ->
        :lists.reverse(5, [3, 4])
      end
    end
  end

  describe "sort/1" do
    test "sorts items in the list" do
      assert :lists.sort([:a, 4, 3.0, :b, 1, 2.0]) == [1, 2.0, 3.0, 4, :a, :b]
    end

    test "raises FunctionClauseError if the argument is not a list" do
      assert_raise FunctionClauseError, "no function clause matching in :lists.sort/1", fn ->
        :lists.sort(:abc)
      end
    end
  end
end
