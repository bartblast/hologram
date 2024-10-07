defmodule Hologram.ExJsConsistency.Erlang.ListsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/lists_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "filter/2" do
    setup do
      [fun: fn elem -> elem > 1 end]
    end

    test "empty list", %{fun: fun} do
      assert :lists.filter(fun, []) == []
    end

    test "non-empty list", %{fun: fun} do
      assert :lists.filter(fun, [1, 2, 3]) == [2, 3]
    end

    test "first arg is not an anonymous function" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.filter/2", [:abc, [1, 2, 3]]),
                   fn ->
                     :lists.filter(:abc, [1, 2, 3])
                   end
    end

    # Client error message is intentionally different than server error message.
    test "first arg is an anonymous function with arity different than 1" do
      expected_msg = ~r"""
      no function clause matching in :lists\.filter/2

      The following arguments were given to :lists\.filter/2:

          # 1
          #Function<[0-9]+\.[0-9]+/2 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\."test filter/2 first arg is an anonymous function with arity different than 1"/1>

          # 2
          \[1, 2, 3\]
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.filter(fn x, y -> x + y > 0 end, [1, 2, 3])
      end
    end

    test "second arg is not a list", %{fun: fun} do
      assert_error ErlangError, build_erlang_error_msg("{:bad_generator, :abc}"), fn ->
        :lists.filter(fun, :abc)
      end
    end

    test "second arg is not a proper list", %{fun: fun} do
      assert_error ErlangError, build_erlang_error_msg("{:bad_generator, 3}"), fn ->
        :lists.filter(fun, [1, 2 | 3])
      end
    end

    test "filter fun doesn't return a boolean" do
      assert_error ErlangError, build_erlang_error_msg("{:bad_filter, 4}"), fn ->
        :lists.filter(fn elem -> 2 * elem end, [2, 3, 4])
      end
    end
  end

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
      expected_msg = build_function_clause_error_msg(":lists.flatten/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.flatten(:abc)
      end
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the argument is an improper list" do
      expected_msg = build_function_clause_error_msg(":lists.do_flatten/2", [5, []])

      assert_error FunctionClauseError,
                   expected_msg,
                   fn ->
                     :lists.flatten([1, [2, 3], 4 | 5])
                   end
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the argument contains a nested improper list" do
      expected_msg = build_function_clause_error_msg(":lists.do_flatten/2", [4, [5]])

      assert_error FunctionClauseError,
                   expected_msg,
                   fn ->
                     :lists.flatten([1, [2, 3 | 4], 5])
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

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the first argument is not an anonymous function" do
      expected_msg = build_function_clause_error_msg(":lists.foldl/3", [:abc, 0, []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.foldl(:abc, 0, [])
      end
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the first argument is an anonymous function with arity different than 2" do
      expected_msg = ~r"""
      no function clause matching in :lists\.foldl/3

      The following arguments were given to :lists\.foldl/3:

          # 1
          #Function<[0-9]+\.[0-9]+/1 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\."test foldl/3 raises FunctionClauseError if the first argument is an anonymous function with arity different than 2"/1>

          # 2
          0

          # 3
          \[\]
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.foldl(fn x -> x end, 0, [])
      end
    end

    test "raises CaseClauseError if the third argument is not a list", %{fun: fun} do
      assert_error CaseClauseError, "no case clause matching: :abc", fn ->
        :lists.foldl(fun, 0, :abc)
      end
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the third argument is an improper list", %{fun: fun} do
      expected_msg = ~r"""
      no function clause matching in :lists\.foldl_1/3

      The following arguments were given to :lists\.foldl_1/3:

          # 1
          #Function<[0-9]+.[0-9]+/2 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\.__ex_unit_setup_[0-9]+_0/1>

          # 2
          3

          # 3
          3
      """s

      assert_error FunctionClauseError,
                   expected_msg,
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
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   fn ->
                     :lists.keyfind(:abc, :xyz, [])
                   end
    end

    test "raises ArgumentError if the second argument (index) is smaller than 1" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   fn ->
                     :lists.keyfind(:abc, 0, [])
                   end
    end

    test "raises ArgumentError if the third argument (tuples) is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a list"),
                   fn ->
                     :lists.keyfind(:abc, 1, :xyz)
                   end
    end

    test "raises ArgumentError if the third argument (tuples) is an improper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a proper list"),
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
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   fn ->
                     :lists.keymember(:abc, :xyz, [])
                   end
    end

    test "raises ArgumentError if the second argument (index) is smaller than 1" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   fn ->
                     :lists.keymember(:abc, 0, [])
                   end
    end

    test "raises ArgumentError if the third argument (tuples) is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a list"),
                   fn ->
                     :lists.keymember(:abc, 1, :xyz)
                   end
    end

    test "raises ArgumentError if the third argument (tuples) is an improper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a proper list"),
                   fn ->
                     :lists.keymember(7, 4, [1, 2 | 3])
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
      expected_msg = build_function_clause_error_msg(":lists.map/2", [:abc, []])

      assert_error FunctionClauseError, expected_msg, fn -> :lists.map(:abc, []) end
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the first argument is an anonymous function with arity different than 1" do
      expected_msg = ~r"""
      no function clause matching in :lists\.map/2

      The following arguments were given to :lists\.map/2:

          # 1
          #Function<[0-9]+\.[0-9]+/2 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\."test map/2 raises FunctionClauseError if the first argument is an anonymous function with arity different than 1"/1>

          # 2
          \[\]
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.map(fn x, y -> x + y end, [])
      end
    end

    test "raises CaseClauseError if the second argument is not a list", %{fun: fun} do
      assert_error CaseClauseError, "no case clause matching: :abc", fn ->
        :lists.map(fun, :abc)
      end
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the second argument is an improper list", %{fun: fun} do
      expected_msg = ~r"""
      no function clause matching in :lists\.map_1/2

      The following arguments were given to :lists\.map_1/2:

          # 1
          #Function<[0-9]+\.[0-9]+/1 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\.__ex_unit_setup_[0-9]+_0/1>

          # 2
          3
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.map(fun, [1, 2 | 3])
      end
    end
  end

  describe "member/2" do
    test "is a member of a proper list" do
      assert :lists.member(2, [1, 2, 3]) == true
    end

    test "is a non-last member of an improper list" do
      assert :lists.member(2, [1, 2 | 3]) == true
    end

    test "is the last member of an improper list" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a proper list"), fn ->
        :lists.member(3, [1, 2 | 3])
      end
    end

    test "is not a member of a proper list" do
      assert :lists.member(4, [1, 2, 3]) == false
    end

    test "is not a member of an improper list" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a proper list"), fn ->
        :lists.member(4, [1, 2 | 3])
      end
    end

    test "uses strict equality" do
      assert :lists.member(2, [1, 2.0, 3]) == false
    end

    test "raises ArgumentError if the second argument is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a list"),
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
      expected_msg = build_function_clause_error_msg(":lists.reverse/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.reverse(:abc)
      end
    end

    test "raises ArgumentError if the argument is not a proper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   fn ->
                     :lists.reverse([1, 2 | 3])
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
      assert_error ArgumentError, build_argument_error_msg(1, "not a proper list"), fn ->
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
      assert_error ArgumentError, build_argument_error_msg(1, "not a list"), fn ->
        :lists.reverse(5, [3, 4])
      end
    end
  end

  describe "sort/1" do
    test "sorts items in the list" do
      assert :lists.sort([:a, 4, 3.0, :b, 1, 2.0]) == [1, 2.0, 3.0, 4, :a, :b]
    end

    test "raises FunctionClauseError if the argument is not a list" do
      expected_msg = build_function_clause_error_msg(":lists.sort/1", [:abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.sort(:abc)
      end
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the argument is an improper list" do
      expected_msg = build_function_clause_error_msg(":lists.split_1/5", [1, 2, 3, [], []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.sort([1, 2 | 3])
      end
    end
  end
end
