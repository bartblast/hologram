defmodule Hologram.ExJsConsistency.Erlang.ListsTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/lists_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "all/2" do
    test "returns false if the first item in the list results in false" do
      assert :lists.all(fn elem -> elem > 1 end, [1, 2, 3, 4]) == false
    end

    test "returns false if the middle item in the list results in false" do
      assert :lists.all(fn elem -> elem > 1 end, [5, 4, 1, 2, 3]) == false
    end

    test "returns false if the last item in the list results in false" do
      assert :lists.all(fn elem -> elem > 1 end, [5, 4, 3, 2, 1]) == false
    end

    test "returns true if all items result in true when supplied to the anonymous function" do
      assert :lists.all(fn elem -> elem > 1 end, [5, 4, 3, 2])
    end

    test "returns true for empty list" do
      assert :lists.all(fn elem -> elem > 1 end, [])
    end

    test "raises FunctionClauseError if the first arg is not an anonymous function" do
      expected_msg = build_function_clause_error_msg(":lists.all/2", [:not_function, [1, 2, 3]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.all(:not_function, [1, 2, 3])
      end
    end

    test "raises FunctionClauseError if the first arg is an anonymous function with arity different than 1" do
      fun = fn x, y -> x == y end

      expected_msg =
        build_function_clause_error_msg(":lists.all/2", [fun, [1, 2, 3]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.all(fun, [1, 2, 3])
      end
    end

    test "raises CaseClauseError if the second argument is not a list" do
      assert_error CaseClauseError, "no case clause matching: :abc", fn ->
        :lists.all(fn elem -> elem > 1 end, :abc)
      end
    end

    test "raises FunctionClauseError if the second argument is an improper list" do
      fun = fn elem -> elem > 0 end

      expected_msg =
        build_function_clause_error_msg(":lists.all_1/2", [fun, 3])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.all(fun, [1, 2 | 3])
      end
    end
  end

  describe "any/2" do
    test "returns true if the first item in the list results in true" do
      assert :lists.any(&(&1 > 2), [3, 1, 2, 0])
    end

    test "returns true if the middle item in the list results in true" do
      assert :lists.any(&(&1 > 2), [0, 1, 3, 2, 0])
    end

    test "returns true if the last item in the list results in true" do
      assert :lists.any(&(&1 > 2), [0, 1, 0, 2, 3])
    end

    test "returns false if none of the items results in true when supplied to the anonymous function" do
      assert :lists.any(&(&1 > 5), [0, 1, 2, 3, 4]) == false
    end

    test "returns false for empty list" do
      assert :lists.any(&(&1 > 2), []) == false
    end

    test "raises FunctionClauseError if the first arg is not an anonymous function" do
      expected_msg = build_function_clause_error_msg(":lists.any/2", [:not_function, [1, 2, 3]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.any(:not_function, [1, 2, 3])
      end
    end

    test "raises FunctionClauseError if the first arg is an anonymous function with arity different than 1" do
      fun = &(&1 == &2)

      expected_msg =
        build_function_clause_error_msg(":lists.any/2", [fun, [1, 2, 3]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.any(fun, [1, 2, 3])
      end
    end

    test "raises CaseClauseError if the second argument is not a list" do
      assert_error CaseClauseError, "no case clause matching: :abc", fn ->
        :lists.any(&(&1 > 2), :abc)
      end
    end

    test "raises FunctionClauseError if the second argument is an improper list" do
      fun = &(&1 > 2)

      expected_msg =
        build_function_clause_error_msg(":lists.any_1/2", [fun, 3])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.any(fun, [1, 2 | 3])
      end
    end
  end

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

  describe "flatmap/2" do
    setup do
      [fun: fn x -> [x, x * 10] end]
    end

    test "returns empty list when given empty list", %{fun: fun} do
      assert :lists.flatmap(fun, []) == []
    end

    test "works with single element list", %{fun: fun} do
      assert :lists.flatmap(fun, [1]) == [1, 10]
    end

    test "works with multiple element list", %{fun: fun} do
      assert :lists.flatmap(fun, [1, 2, 3]) == [1, 10, 2, 20, 3, 30]
    end

    test "returns empty list when mapper returns empty lists" do
      assert :lists.flatmap(fn _x -> [] end, [1, 2, 3]) == []
    end

    test "flattens only one level" do
      assert :lists.flatmap(fn x -> [[[x]]] end, [1, 2]) == [[[1]], [[2]]]
    end

    test "raises FunctionClauseError if the first argument is not an anonymous function" do
      expected_msg = build_function_clause_error_msg(":lists.flatmap/2", [:abc, []])

      assert_error FunctionClauseError, expected_msg, fn -> :lists.flatmap(:abc, []) end
    end

    test "raises FunctionClauseError if the first argument is an anonymous function with arity different than 1" do
      expected_msg = ~r"""
      no function clause matching in :lists\.flatmap/2

      The following arguments were given to :lists\.flatmap/2:

          # 1
          #Function<[0-9]+\.[0-9]+/2 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\."test flatmap/2 raises FunctionClauseError if the first argument is an anonymous function with arity different than 1"/1>

          # 2
          \[\]
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.flatmap(fn x, y -> x + y end, [])
      end
    end

    test "raises FunctionClauseError if the second argument is not a list", %{fun: fun} do
      expected_msg = ~r"""
      no function clause matching in :lists\.flatmap_1/2

      The following arguments were given to :lists\.flatmap_1/2:

          # 1
          #Function<[0-9]+\.[0-9]+/1 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\.__ex_unit_setup_[0-9]+_0/1>

          # 2
          :abc
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.flatmap(fun, :abc)
      end
    end

    test "raises FunctionClauseError if the second argument is an improper list", %{fun: fun} do
      expected_msg = build_function_clause_error_msg(":lists.flatmap_1/2", [fun, 3])

      assert_error FunctionClauseError, expected_msg, fn -> :lists.flatmap(fun, [1, 2 | 3]) end
    end

    test "raises ArgumentError if the mapper does not return a proper list" do
      assert_error ArgumentError, "argument error", fn ->
        :lists.flatmap(fn x -> x * 10 end, [1, 2, 3])
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

  describe "flatten/2" do
    test "empty list and empty tail" do
      assert :lists.flatten([], []) == []
    end

    test "empty list and non-empty tail" do
      assert :lists.flatten([], [1, 2, 3]) == [1, 2, 3]
    end

    test "non-nested list and empty tail" do
      assert :lists.flatten([1, 2, 3], []) == [1, 2, 3]
    end

    test "non-nested list and non-empty tail" do
      assert :lists.flatten([1, 2, 3], [4, 5, 6]) == [1, 2, 3, 4, 5, 6]
    end

    test "nested list and non-empty tail" do
      assert :lists.flatten([1, [2, [3, 4]]], [5, 6]) == [1, 2, 3, 4, 5, 6]
    end

    test "deeply nested empty lists" do
      assert :lists.flatten([[], [[]]], [1, 2]) == [1, 2]
    end

    test "improper tail" do
      assert :lists.flatten([1, 2], [3, 4 | 5]) == [1, 2, 3, 4 | 5]
    end

    test "raises FunctionClauseError if the first argument is not a list" do
      expected_msg = build_function_clause_error_msg(":lists.flatten/2", [:abc, [1, 2]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.flatten(:abc, [1, 2])
      end
    end

    test "raises FunctionClauseError if the first argument is an improper list" do
      expected_msg = build_function_clause_error_msg(":lists.do_flatten/2", [3, [4, 5]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.flatten([1, 2 | 3], [4, 5])
      end
    end

    test "raises FunctionClauseError if the first argument contains a nested improper list" do
      expected_msg = build_function_clause_error_msg(":lists.do_flatten/2", [4, [5, 6]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.flatten([1, [2, 3 | 4]], [5, 6])
      end
    end

    test "raises FunctionClauseError if the second argument is not a list" do
      expected_msg = build_function_clause_error_msg(":lists.flatten/2", [[1, 2], :abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.flatten([1, 2], :abc)
      end
    end
  end

  describe "foldl/3" do
    setup do
      [fun: fn elem, acc -> [elem | acc] end]
    end

    test "reduces empty list", %{fun: fun} do
      assert :lists.foldl(fun, [], []) == []
    end

    test "reduces non-empty list", %{fun: fun} do
      assert :lists.foldl(fun, [], [1, 2, 3]) == [3, 2, 1]
    end

    test "raises FunctionClauseError if the first argument is not an anonymous function" do
      expected_msg = build_function_clause_error_msg(":lists.foldl/3", [:abc, [], []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.foldl(:abc, [], [])
      end
    end

    test "raises FunctionClauseError if the first argument is an anonymous function with arity different than 2" do
      expected_msg = ~r"""
      no function clause matching in :lists\.foldl/3

      The following arguments were given to :lists\.foldl/3:

          # 1
          #Function<[0-9]+\.[0-9]+/1 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\."test foldl/3 raises FunctionClauseError if the first argument is an anonymous function with arity different than 2"/1>

          # 2
          \[\]

          # 3
          \[\]
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.foldl(fn x -> x end, [], [])
      end
    end

    test "raises CaseClauseError if the third argument is not a list", %{fun: fun} do
      assert_error CaseClauseError, "no case clause matching: :abc", fn ->
        :lists.foldl(fun, [], :abc)
      end
    end

    test "raises FunctionClauseError if the third argument is an improper list", %{fun: fun} do
      expected_msg = ~r"""
      no function clause matching in :lists\.foldl_1/3

      The following arguments were given to :lists\.foldl_1/3:

          # 1
          #Function<[0-9]+.[0-9]+/2 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\.__ex_unit_setup_[0-9]+_0/1>

          # 2
          \[2, 1\]

          # 3
          3
      """s

      assert_error FunctionClauseError,
                   expected_msg,
                   fn ->
                     :lists.foldl(fun, [], [1, 2 | 3])
                   end
    end
  end

  describe "foldr/3" do
    setup do
      [fun: fn elem, acc -> [elem | acc] end]
    end

    test "reduces empty list", %{fun: fun} do
      assert :lists.foldr(fun, [], []) == []
    end

    test "reduces non-empty list", %{fun: fun} do
      assert :lists.foldr(fun, [], [1, 2, 3]) == [1, 2, 3]
    end

    test "raises FunctionClauseError if the first argument is not an anonymous function" do
      expected_msg = build_function_clause_error_msg(":lists.foldr/3", [:abc, [], []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.foldr(:abc, [], [])
      end
    end

    test "raises FunctionClauseError if the first argument is an anonymous function with arity different than 2" do
      expected_msg = ~r"""
      no function clause matching in :lists\.foldr/3

      The following arguments were given to :lists\.foldr/3:

          # 1
          #Function<[0-9]+\.[0-9]+/1 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\."test foldr/3 raises FunctionClauseError if the first argument is an anonymous function with arity different than 2"/1>

          # 2
          \[\]

          # 3
          \[\]
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.foldr(fn x -> x end, [], [])
      end
    end

    test "raises FunctionClauseError if the third argument is not a list", %{fun: fun} do
      expected_msg = ~r"""
      no function clause matching in :lists\.foldr_1/3

      The following arguments were given to :lists\.foldr_1/3:

          # 1
          #Function<[0-9]+.[0-9]+/2 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\.__ex_unit_setup_[0-9]+_0/1>

          # 2
          \[\]

          # 3
          :abc
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.foldr(fun, [], :abc)
      end
    end

    test "raises FunctionClauseError if the third argument is an improper list", %{fun: fun} do
      expected_msg = ~r"""
      no function clause matching in :lists\.foldr_1/3

      The following arguments were given to :lists\.foldr_1/3:

          # 1
          #Function<[0-9]+.[0-9]+/2 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\.__ex_unit_setup_[0-9]+_0/1>

          # 2
          \[\]

          # 3
          3
      """s

      assert_error FunctionClauseError,
                   expected_msg,
                   fn ->
                     :lists.foldr(fun, [], [1, 2 | 3])
                   end
    end
  end

  describe "keydelete/3" do
    test "returns the original list if tuples list is empty" do
      assert :lists.keydelete(:c, 1, []) == []
    end

    test "single tuple, no match" do
      assert :lists.keydelete(:c, 1, [{:a, 2, 3.0}]) == [{:a, 2, 3.0}]
    end

    test "single tuple, match at first index" do
      assert :lists.keydelete(:a, 1, [{:a, 2, 3.0}]) == []
    end

    test "single tuple, match at middle index" do
      assert :lists.keydelete(:b, 2, [{1, :b, 3.0}]) == []
    end

    test "single tuple, match at last index" do
      assert :lists.keydelete(:c, 3, [{1, 2.0, :c}]) == []
    end

    test "multiple tuples, no match" do
      tuples = [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]

      assert :lists.keydelete(:c, 1, tuples) == [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]
    end

    test "multiple tuples, match first tuple" do
      tuples = [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]

      assert :lists.keydelete(:a, 1, tuples) == [{:d, :e, :f}, {:g, :h, :i}]
    end

    test "multiple tuples, match middle tuple" do
      tuples = [{:d, :e, :f}, {:a, 2, 3.0}, {:g, :h, :i}]

      assert :lists.keydelete(:a, 1, tuples) == [{:d, :e, :f}, {:g, :h, :i}]
    end

    test "multiple tuples, match last tuple" do
      tuples = [{:d, :e, :f}, {:g, :h, :i}, {:a, 2, 3.0}]

      assert :lists.keydelete(:a, 1, tuples) == [{:d, :e, :f}, {:g, :h, :i}]
    end

    test "applies non-strict comparison" do
      assert :lists.keydelete(2, 1, [{2.0}]) == []
    end

    test "raises FunctionClauseError if the second argument (index) is not an integer" do
      expected_msg = build_function_clause_error_msg(":lists.keydelete/3", [:a, 2.0, []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keydelete(:a, 2.0, [])
      end
    end

    test "raises FunctionClauseError if the second argument (index) is smaller than 1" do
      expected_msg = build_function_clause_error_msg(":lists.keydelete/3", [:a, 0, []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keydelete(:a, 0, [])
      end
    end

    test "raises FunctionClauseError if the third argument (tuples) is not a list" do
      expected_msg = build_function_clause_error_msg(":lists.keydelete3/3", [:a, 1, {{:b}, {:c}}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keydelete(:a, 1, {{:b}, {:c}})
      end
    end

    test "raises FunctionClauseError if the third argument (tuples) is an improper list" do
      expected_msg = build_function_clause_error_msg(":lists.keydelete3/3", [:a, 1, {:d}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keydelete(:a, 1, [{:b}, {:c} | {:d}])
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

  describe "keyreplace/4" do
    test "returns the original list if tuples list is empty" do
      assert :lists.keyreplace(:c, 1, [], {:x}) == []
    end

    test "single tuple, no match" do
      assert :lists.keyreplace(:c, 1, [{:a, 2, 3.0}], {:x}) == [{:a, 2, 3.0}]
    end

    test "single tuple, match at first index" do
      assert :lists.keyreplace(:a, 1, [{:a, 2, 3.0}], {:x}) == [{:x}]
    end

    test "single tuple, match at middle index" do
      assert :lists.keyreplace(:b, 2, [{1, :b, 3.0}], {:x}) == [{:x}]
    end

    test "single tuple, match at last index" do
      assert :lists.keyreplace(:c, 3, [{1, 2.0, :c}], {:x}) == [{:x}]
    end

    test "multiple tuples, no match" do
      tuples = [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]

      assert :lists.keyreplace(:c, 1, tuples, {:x}) == [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]
    end

    test "multiple tuples, match first tuple" do
      tuples = [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]

      assert :lists.keyreplace(:a, 1, tuples, {:x}) == [{:x}, {:d, :e, :f}, {:g, :h, :i}]
    end

    test "multiple tuples, match middle tuple" do
      tuples = [{:d, :e, :f}, {:a, 2, 3.0}, {:g, :h, :i}]

      assert :lists.keyreplace(:a, 1, tuples, {:x}) == [{:d, :e, :f}, {:x}, {:g, :h, :i}]
    end

    test "multiple tuples, match last tuple" do
      tuples = [{:d, :e, :f}, {:g, :h, :i}, {:a, 2, 3.0}]

      assert :lists.keyreplace(:a, 1, tuples, {:x}) == [{:d, :e, :f}, {:g, :h, :i}, {:x}]
    end

    test "applies non-strict comparison" do
      assert :lists.keyreplace(2, 1, [{2.0}], {:x}) == [{:x}]
    end

    test "raises FunctionClauseError if the second argument (index) is not an integer" do
      expected_msg = build_function_clause_error_msg(":lists.keyreplace/4", [:a, 2.0, [], {}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keyreplace(:a, 2.0, [], {})
      end
    end

    test "raises FunctionClauseError if the second argument (index) is smaller than 1" do
      expected_msg = build_function_clause_error_msg(":lists.keyreplace/4", [:a, 0, [], {}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keyreplace(:a, 0, [], {})
      end
    end

    test "raises FunctionClauseError if the third argument (tuples) is not a list" do
      expected_msg =
        build_function_clause_error_msg(":lists.keyreplace3/4", [:a, 1, {{:b}, {:c}}, {}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keyreplace(:a, 1, {{:b}, {:c}}, {})
      end
    end

    test "raises FunctionClauseError if the third argument (tuples) is an improper list" do
      expected_msg = build_function_clause_error_msg(":lists.keyreplace3/4", [:a, 1, {:d}, {}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keyreplace(:a, 1, [{:b}, {:c} | {:d}], {})
      end
    end

    test "raises FunctionClauseError if the fourth argument (newTuple) is not a tuple" do
      expected_msg = build_function_clause_error_msg(":lists.keyreplace/4", [:a, 1, [], :x])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keyreplace(:a, 1, [], :x)
      end
    end
  end

  describe "keysort/2" do
    test "returns the empty list if the input is the empty list" do
      assert :lists.keysort(3, []) === []
    end

    test "returns the unchanged one-element list" do
      assert :lists.keysort(1, [{:a, 2}]) === [{:a, 2}]
    end

    test "returns the unchanged one-element list even if the index is out of range of the tuple" do
      assert :lists.keysort(3, [{:a}]) === [{:a}]
    end

    test "returns the unchanged one-element list even if the element is not a tuple" do
      assert :lists.keysort(3, [:a]) === [:a]
    end

    test "sorts the list by the first element of each tuple" do
      assert :lists.keysort(1, [{:b, 1}, {:a, 2}]) === [{:a, 2}, {:b, 1}]
    end

    test "sorts the list by the middle element of each tuple" do
      assert :lists.keysort(2, [{:a, 2, :c}, {:b, 1, :d}]) === [{:b, 1, :d}, {:a, 2, :c}]
    end

    test "sorts the list by the last element of each tuple" do
      assert :lists.keysort(2, [{:a, 2}, {:b, 1}]) === [{:b, 1}, {:a, 2}]
    end

    test "is stable (preserves order of elements)" do
      tuples = [{4, :h}, {1, :a}, {1, :b}, {3, :f}, {3, :g}, {1, :c}, {1, :d}, {2, :e}]
      result = :lists.keysort(1, tuples)
      expected = [{1, :a}, {1, :b}, {1, :c}, {1, :d}, {2, :e}, {3, :f}, {3, :g}, {4, :h}]

      assert result == expected
    end

    test "raises FunctionClauseError if the first argument is not an integer" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.keysort/2", [1.0, []]),
                   fn -> :lists.keysort(1.0, []) end
    end

    test "raises FunctionClauseError if the first argument is zero integer" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.keysort/2", [0, []]),
                   fn -> :lists.keysort(0, []) end
    end

    test "raises FunctionClauseError if the first argument is a negative integer" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.keysort/2", [-1, []]),
                   fn -> :lists.keysort(-1, []) end
    end

    test "raises CaseClauseError if the second argument is not a list" do
      assert_error CaseClauseError,
                   "no case clause matching: :a",
                   fn -> :lists.keysort(1, :a) end
    end

    test "raises CaseClauseError if the second argument is a two-element improper list" do
      assert_error CaseClauseError,
                   "no case clause matching: [1 | 2]",
                   fn -> :lists.keysort(1, [1 | 2]) end
    end

    test "raises FunctionClauseError if the second argument is a larger improper list of tuples" do
      expected_msg =
        build_function_clause_error_msg(":lists.keysplit_1/8", [
          1,
          {:a},
          :a,
          {:b},
          :b,
          {:c},
          [],
          []
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keysort(1, [{:a}, {:b} | {:c}])
      end
    end

    test "raises ArgumentError if the second argument is a larger improper list of non tuples" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a tuple"),
                   fn -> :lists.keysort(1, [1, 2 | 3]) end
    end

    test "raises ArgumentError if an element of the list is not a tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a tuple"),
                   fn -> :lists.keysort(1, [{:a}, :b]) end
    end

    test "raises ArgumentError if the index is out of range for any tuple in the list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "out of range"),
                   fn -> :lists.keysort(1, [{:a}, {}]) end
    end
  end

  describe "keystore/4" do
    test "appends the new tuple if tuples list is empty" do
      assert :lists.keystore(:c, 1, [], {:x}) == [{:x}]
    end

    test "single tuple, no match" do
      assert :lists.keystore(:c, 1, [{:a, 2, 3.0}], {:x}) == [{:a, 2, 3.0}, {:x}]
    end

    test "single tuple, match at first index" do
      assert :lists.keystore(:a, 1, [{:a, 2, 3.0}], {:x}) == [{:x}]
    end

    test "single tuple, match at middle index" do
      assert :lists.keystore(:b, 2, [{1, :b, 3.0}], {:x}) == [{:x}]
    end

    test "single tuple, match at last index" do
      assert :lists.keystore(:c, 3, [{1, 2.0, :c}], {:x}) == [{:x}]
    end

    test "multiple tuples, no match" do
      tuples = [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]

      assert :lists.keystore(:c, 1, tuples, {:x}) == [
               {:a, 2, 3.0},
               {:d, :e, :f},
               {:g, :h, :i},
               {:x}
             ]
    end

    test "multiple tuples, match first tuple" do
      tuples = [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]

      assert :lists.keystore(:a, 1, tuples, {:x}) == [{:x}, {:d, :e, :f}, {:g, :h, :i}]
    end

    test "multiple tuples, match middle tuple" do
      tuples = [{:d, :e, :f}, {:a, 2, 3.0}, {:g, :h, :i}]

      assert :lists.keystore(:a, 1, tuples, {:x}) == [{:d, :e, :f}, {:x}, {:g, :h, :i}]
    end

    test "multiple tuples, match last tuple" do
      tuples = [{:d, :e, :f}, {:g, :h, :i}, {:a, 2, 3.0}]

      assert :lists.keystore(:a, 1, tuples, {:x}) == [{:d, :e, :f}, {:g, :h, :i}, {:x}]
    end

    test "skips tuple when its size is smaller than the index" do
      tuples = [{:a}, {:b, :a, :c}]

      assert :lists.keystore(:a, 2, tuples, {:x}) == [{:a}, {:x}]
    end

    test "replaces only the first matching tuple" do
      tuples = [{:a, 1}, {:a, 2}]

      assert :lists.keystore(:a, 1, tuples, {:x}) == [{:x}, {:a, 2}]
    end

    test "applies non-strict comparison" do
      assert :lists.keystore(2, 1, [{2.0}], {:x}) == [{:x}]
    end

    test "raises FunctionClauseError if the second argument (index) is not an integer" do
      expected_msg = build_function_clause_error_msg(":lists.keystore/4", [:a, 2.0, [], {}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keystore(:a, 2.0, [], {})
      end
    end

    test "raises FunctionClauseError if the second argument (index) is smaller than 1" do
      expected_msg = build_function_clause_error_msg(":lists.keystore/4", [:a, 0, [], {}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keystore(:a, 0, [], {})
      end
    end

    test "raises FunctionClauseError if the third argument (tuples) is not a list" do
      expected_msg =
        build_function_clause_error_msg(":lists.keystore2/4", [:a, 1, {{:b}, {:c}}, {}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keystore(:a, 1, {{:b}, {:c}}, {})
      end
    end

    test "raises FunctionClauseError if the third argument (tuples) is an improper list" do
      expected_msg = build_function_clause_error_msg(":lists.keystore2/4", [:a, 1, {:d}, {}])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keystore(:a, 1, [{:b}, {:c} | {:d}], {})
      end
    end

    test "raises FunctionClauseError if the fourth argument (newTuple) is not a tuple" do
      expected_msg = build_function_clause_error_msg(":lists.keystore/4", [:a, 1, [], :x])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keystore(:a, 1, [], :x)
      end
    end
  end

  describe "keytake/3" do
    test "returns false if tuples list is empty" do
      assert :lists.keytake(:c, 1, []) == false
    end

    test "single tuple, no match" do
      assert :lists.keytake(:c, 1, [{:a, 2, 3.0}]) == false
    end

    test "single tuple, match at first index" do
      assert :lists.keytake(:a, 1, [{:a, 2, 3.0}]) == {:value, {:a, 2, 3.0}, []}
    end

    test "single tuple, match at middle index" do
      assert :lists.keytake(:b, 2, [{1, :b, 3.0}]) == {:value, {1, :b, 3.0}, []}
    end

    test "single tuple, match at last index" do
      assert :lists.keytake(:c, 3, [{1, 2.0, :c}]) == {:value, {1, 2.0, :c}, []}
    end

    test "multiple tuples, no match" do
      tuples = [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]

      assert :lists.keytake(:c, 1, tuples) == false
    end

    test "multiple tuples, match first tuple" do
      tuples = [{:a, 2, 3.0}, {:d, :e, :f}, {:g, :h, :i}]

      assert :lists.keytake(:a, 1, tuples) == {:value, {:a, 2, 3.0}, [{:d, :e, :f}, {:g, :h, :i}]}
    end

    test "multiple tuples, match middle tuple" do
      tuples = [{:d, :e, :f}, {:a, 2, 3.0}, {:g, :h, :i}]

      assert :lists.keytake(:a, 1, tuples) == {:value, {:a, 2, 3.0}, [{:d, :e, :f}, {:g, :h, :i}]}
    end

    test "multiple tuples, match last tuple" do
      tuples = [{:d, :e, :f}, {:g, :h, :i}, {:a, 2, 3.0}]

      assert :lists.keytake(:a, 1, tuples) == {:value, {:a, 2, 3.0}, [{:d, :e, :f}, {:g, :h, :i}]}
    end

    test "skips tuple when its size is smaller than the index" do
      tuples = [{:a}, {:b, :a, :c}]

      assert :lists.keytake(:a, 2, tuples) == {:value, {:b, :a, :c}, [{:a}]}
    end

    test "returns only the first matching tuple" do
      tuples = [{:a, 1}, {:a, 2}]

      assert :lists.keytake(:a, 1, tuples) == {:value, {:a, 1}, [{:a, 2}]}
    end

    test "applies non-strict comparison" do
      assert :lists.keytake(2, 1, [{2.0}]) == {:value, {2.0}, []}
    end

    test "raises FunctionClauseError if the second argument (index) is not an integer" do
      expected_msg = build_function_clause_error_msg(":lists.keytake/3", [:a, 2.0, []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keytake(:a, 2.0, [])
      end
    end

    test "raises FunctionClauseError if the second argument (index) is smaller than 1" do
      expected_msg = build_function_clause_error_msg(":lists.keytake/3", [:a, 0, []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keytake(:a, 0, [])
      end
    end

    test "raises FunctionClauseError if the third argument (tuples) is not a list" do
      expected_msg =
        build_function_clause_error_msg(":lists.keytake/4", [:a, 1, {{:b}, {:c}}, []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keytake(:a, 1, {{:b}, {:c}})
      end
    end

    test "raises FunctionClauseError if the third argument (tuples) is an improper list" do
      expected_msg =
        build_function_clause_error_msg(":lists.keytake/4", [:a, 1, {:d}, [{:c}, {:b}]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.keytake(:a, 1, [{:b}, {:c} | {:d}])
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

  describe "mapfoldl/3" do
    setup do
      [fun: fn elem, acc -> {elem * 10, acc + elem} end]
    end

    test "mapfolds empty list", %{fun: fun} do
      assert :lists.mapfoldl(fun, 0, []) == {[], 0}
    end

    test "mapfolds non-empty list", %{fun: fun} do
      assert :lists.mapfoldl(fun, 0, [1, 2, 3]) == {[10, 20, 30], 6}
    end

    test "raises FunctionClauseError if the first argument is not an anonymous function" do
      expected_msg =
        build_function_clause_error_msg(":lists.mapfoldl/3", [:abc, 0, []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.mapfoldl(:abc, 0, [])
      end
    end

    test "raises FunctionClauseError if the first argument is an anonymous function with arity different than 2" do
      expected_msg = ~r"""
      no function clause matching in :lists\.mapfoldl/3

      The following arguments were given to :lists\.mapfoldl/3:

          # 1
          #Function<[0-9]+\.[0-9]+/1 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\."test mapfoldl/3 raises FunctionClauseError if the first argument is an anonymous function with arity different than 2"/1>

          # 2
          0

          # 3
          \[\]
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.mapfoldl(fn elem -> elem end, 0, [])
      end
    end

    test "raises FunctionClauseError if the third argument is not a list", %{fun: fun} do
      expected_msg =
        build_function_clause_error_msg(":lists.mapfoldl_1/3", [fun, 0, :abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.mapfoldl(fun, 0, :abc)
      end
    end

    test "raises FunctionClauseError if the third argument is an improper list", %{fun: fun} do
      expected_msg = ~r"""
      no function clause matching in :lists\.mapfoldl_1/3

      The following arguments were given to :lists\.mapfoldl_1/3:

          # 1
          #Function<[0-9]+\.[0-9]+/2 in Hologram\.ExJsConsistency\.Erlang\.ListsTest\.__ex_unit_setup_[0-9]+_0/1>

          # 2
          3

          # 3
          3
      """s

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.mapfoldl(fun, 0, [1, 2 | 3])
      end
    end

    test "raises MatchError if the anonymous function does not return a 2-element tuple" do
      assert_error MatchError, build_match_error_msg(1), fn ->
        :lists.mapfoldl(fn elem, acc -> elem + acc end, 0, [1])
      end
    end
  end

  describe "max/1" do
    test "returns the element from a list of length 1" do
      assert :lists.max([3]) == 3
    end

    test "returns the larger element from a list of size 2 with second being largest" do
      assert :lists.max([1, 3]) == 3
    end

    test "returns the larger element from a list of size 2 with first being largest" do
      assert :lists.max([3, 1]) == 3
    end

    test "returns the element from a list of size 2 when both are the same" do
      assert :lists.max([3, 3]) == 3
    end

    test "applies structural comparison" do
      list = Enum.shuffle([:a, 2.0, 3, "d", pid("0.1.2"), {0, 1}])

      assert :lists.max(list) == "d"
    end

    test "returns the largest element from a large list with many duplicates" do
      list = Enum.shuffle([1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5])

      assert :lists.max(list) == 5
    end

    test "raises FunctionClauseError if the argument is not a list" do
      expected_msg = build_function_clause_error_msg(":lists.max/1")

      assert_raise FunctionClauseError, expected_msg, fn ->
        :lists.max(:abc)
      end
    end

    test "raises FunctionClauseError if the argument is an improper list" do
      # Notice that the error message says :lists.max/2 (not :lists.max/1)
      # :lists.max/2 is (probably) a private Erlang function that get's called by :lists.max/1
      expected_msg = build_function_clause_error_msg(":lists.max/2")

      assert_raise FunctionClauseError, expected_msg, fn ->
        :lists.max([1, 2 | 3])
      end
    end

    test "raises FunctionClauseError if the argument is an empty list" do
      expected_msg = build_function_clause_error_msg(":lists.max/1")

      assert_raise FunctionClauseError, expected_msg, fn ->
        :lists.max([])
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

  describe "min/1" do
    test "returns the element from a list of length 1" do
      assert :lists.min([3]) == 3
    end

    test "returns the smaller element from a list of size 2 with first being smallest" do
      assert :lists.min([1, 3]) == 1
    end

    test "returns the smaller element from a list of size 2 with second being smallest" do
      assert :lists.min([3, 1]) == 1
    end

    test "returns the element from a list of size 2 when both are the same" do
      assert :lists.min([3, 3]) == 3
    end

    test "applies structural comparison" do
      list = Enum.shuffle([:a, 2.0, 3, "d", pid("0.1.2"), {0, 1}])

      assert :lists.min(list) == 2.0
    end

    test "returns the smallest element from a large list with many duplicates" do
      list = Enum.shuffle([1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5])

      assert :lists.min(list) == 1
    end

    test "raises FunctionClauseError if the argument is not a list" do
      expected_msg = build_function_clause_error_msg(":lists.min/1")

      assert_raise FunctionClauseError, expected_msg, fn ->
        :lists.min(:abc)
      end
    end

    test "raises FunctionClauseError if the argument is an improper list" do
      # Notice that the error message says :lists.min/2 (not :lists.min/1)
      # :lists.min/2 is (probably) a private Erlang function that get's called by :lists.min/1
      expected_msg = build_function_clause_error_msg(":lists.min/2")

      assert_raise FunctionClauseError, expected_msg, fn ->
        :lists.min([1, 2 | 3])
      end
    end

    test "raises FunctionClauseError if the argument is an empty list" do
      expected_msg = build_function_clause_error_msg(":lists.min/1")

      assert_raise FunctionClauseError, expected_msg, fn ->
        :lists.min([])
      end
    end
  end

  describe "prefix/2" do
    test "returns true if the first one-element list is a prefix of the second list" do
      assert :lists.prefix([1], [1, 2])
    end

    test "returns true if the first multiple-element list is a prefix of the second list" do
      assert :lists.prefix([1, 2], [1, 2, 3])
    end

    test "returns true if the lists are the same" do
      assert :lists.prefix([1, 2], [1, 2])
    end

    test "returns true if both lists contain the same single element" do
      assert :lists.prefix([1], [1])
    end

    test "returns true if both lists are empty" do
      assert :lists.prefix([], [])
    end

    test "returns true when the first list is empty" do
      assert :lists.prefix([], [1, 2])
    end

    test "returns false if the first list is not a prefix of the second list" do
      refute :lists.prefix([1, 2], [1])
    end

    test "returns false if the first list has an element that differs from the corresponding element in the second list" do
      refute :lists.prefix([1, 3], [1, 2, 3])
    end

    test "returns false if the first argument is an improper list that has no common prefix with the second proper list" do
      refute :lists.prefix([1 | 2], [3, 4])
    end

    test "returns false if the first argument is an improper list that shares a shorter prefix with the second proper list" do
      refute :lists.prefix([1, 2 | 3], [1, 4])
    end

    test "returns false if the second argument is an improper list that has no common prefix with the first proper list" do
      refute :lists.prefix([1, 2], [3 | 4])
    end

    test "returns false if the second argument is an improper list that shares a shorter prefix with the first proper list" do
      refute :lists.prefix([1, 4], [1, 2 | 3])
    end

    test "returns false if both lists are improper with no common prefix" do
      refute :lists.prefix([1 | 2], [3 | 4])
    end

    test "returns false if both lists are improper with a common shorter prefix" do
      refute :lists.prefix([1, 2 | 3], [1, 4 | 3])
    end

    test "raises FunctionClauseError if the first argument is not a list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.prefix/2", [:a, [1, 2]]),
                   {:lists, :prefix, [:a, [1, 2]]}
    end

    test "raises FunctionClauseError if the second argument is not a list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.prefix/2", [[1, 2], :a]),
                   {:lists, :prefix, [[1, 2], :a]}
    end

    test "raises FunctionClauseError if the first argument is an improper list where everything but the last element is a prefix of the second proper list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.prefix/2", [3, []]),
                   {:lists, :prefix, [[1, 2 | 3], [1, 2]]}
    end

    test "raises FunctionClauseError if the second argument is an improper list where everything but the last element is a prefix of the first proper list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.prefix/2", [[], 3]),
                   {:lists, :prefix, [[1, 2], [1, 2 | 3]]}
    end

    test "raises FunctionClauseError if both lists are improper and have a common prefix made of everything but the last element" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.prefix/2", [3, 4]),
                   {:lists, :prefix, [[1, 2 | 3], [1, 2 | 4]]}
    end

    test "raises FunctionClauseError if the first improper list would be a prefix of the second improper list had the first list been proper" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":lists.prefix/2", [3, [3 | 4]]),
                   {:lists, :prefix, [[1, 2 | 3], [1, 2, 3 | 4]]}
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

  describe "seq/2" do
    test "delegates to seq/3 with increment = 1" do
      assert :lists.seq(3, 5) == :lists.seq(3, 5, 1)
    end

    test "raises FunctionClauseError if the first argument is not an integer" do
      expected_msg = build_function_clause_error_msg(":lists.seq/2", [:abc, 5])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.seq(:abc, 5)
      end
    end

    test "raises FunctionClauseError if the second argument is not an integer" do
      expected_msg = build_function_clause_error_msg(":lists.seq/2", [1, :abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.seq(1, :abc)
      end
    end

    test "raises FunctionClauseError when from > to + 1" do
      expected_msg = build_function_clause_error_msg(":lists.seq/2", [10, 5])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.seq(10, 5)
      end
    end
  end

  describe "seq/3" do
    test "generates ascending sequence with increment 1" do
      assert :lists.seq(3, 5, 1) == [3, 4, 5]
    end

    test "generates ascending sequence with increment 2" do
      assert :lists.seq(1, 10, 2) == [1, 3, 5, 7, 9]
    end

    test "generates ascending sequence from negative to positive" do
      assert :lists.seq(-5, 5, 2) == [-5, -3, -1, 1, 3, 5]
    end

    test "generates descending sequence with negative increment" do
      assert :lists.seq(10, 5, -1) == [10, 9, 8, 7, 6, 5]
    end

    test "generates descending sequence with negative increment of -2" do
      assert :lists.seq(10, 1, -2) == [10, 8, 6, 4, 2]
    end

    test "generates descending sequence in negative range" do
      assert :lists.seq(-1, -10, -2) == [-1, -3, -5, -7, -9]
    end

    test "generates single element sequence when from equals to" do
      assert :lists.seq(5, 5, 1) == [5]
    end

    test "generates single element sequence when from equals to with increment 0" do
      assert :lists.seq(5, 5, 0) == [5]
    end

    test "generates empty sequence if from > to with positive increment" do
      assert :lists.seq(10, 6, 4) == []
    end

    test "generates empty sequence when from - incr equals to (boundary case)" do
      assert :lists.seq(3, 2, 1) == []
    end

    test "generates empty sequence if from < to with negative increment" do
      assert :lists.seq(6, 7, -1) == []
    end

    test "raises ArgumentError if the first argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an integer"),
                   fn ->
                     :lists.seq(:abc, 5, 1)
                   end
    end

    test "raises ArgumentError if the second argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   fn ->
                     :lists.seq(1, :abc, 1)
                   end
    end

    test "raises ArgumentError if the third argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not an integer"),
                   fn ->
                     :lists.seq(1, 5, :abc)
                   end
    end

    test "raises ArgumentError if from > to with positive increment" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a negative increment"),
                   fn ->
                     :lists.seq(10, 1, 1)
                   end
    end

    test "raises ArgumentError if from < to with negative increment" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a positive increment"),
                   fn ->
                     :lists.seq(1, 10, -1)
                   end
    end

    test "raises ArgumentError if increment is 0" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a positive increment"),
                   fn ->
                     :lists.seq(1, 5, 0)
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

  describe "sort/2" do
    setup do
      [fun: fn a, b -> a <= b end]
    end

    test "sorts list using custom comparison function", %{fun: fun} do
      assert :lists.sort(fun, [3, 1, 4, 2]) == [1, 2, 3, 4]
    end

    test "returns empty list when sorting empty list", %{fun: fun} do
      assert :lists.sort(fun, []) == []
    end

    test "returns same list when sorting single element list", %{fun: fun} do
      assert :lists.sort(fun, [5]) == [5]
    end

    test "returns same list when already sorted", %{fun: fun} do
      assert :lists.sort(fun, [1, 2, 3, 4]) == [1, 2, 3, 4]
    end

    test "preserves duplicate elements", %{fun: fun} do
      assert :lists.sort(fun, [3, 1, 2, 1, 3]) == [1, 1, 2, 3, 3]
    end

    test "sorts list in reverse order" do
      fun = fn a, b -> a >= b end

      assert :lists.sort(fun, [3, 1, 4, 2]) == [4, 3, 2, 1]
    end

    test "raises BadFunctionError if the first argument is not a function" do
      expected_msg = "expected a function, got: :abc"

      assert_error BadFunctionError, expected_msg, fn ->
        :lists.sort(:abc, [1, 2])
      end
    end

    test "raises BadArityError if the first argument is a function with wrong arity" do
      expected_msg = ~r/with arity 1 called with 2 arguments \(\d+, \d+\)/

      assert_error BadArityError, expected_msg, fn ->
        :lists.sort(fn x -> x end, [1, 2])
      end
    end

    test "raises FunctionClauseError if the second argument is not a list", %{fun: fun} do
      expected_msg = build_function_clause_error_msg(":lists.sort/2", [fun, :abc])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.sort(fun, :abc)
      end
    end

    test "raises FunctionClauseError if the second argument is an improper list with 2 elements",
         %{fun: fun} do
      expected_msg = build_function_clause_error_msg(":lists.sort/2", [fun, [1 | 2]])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.sort(fun, [1 | 2])
      end
    end

    test "raises FunctionClauseError if the second argument is an improper list with at least 3 elements",
         %{
           fun: fun
         } do
      expected_msg = build_function_clause_error_msg(":lists.fsplit_1/6", [2, 1, fun, 3, [], []])

      assert_error FunctionClauseError, expected_msg, fn ->
        :lists.sort(fun, [1, 2 | 3])
      end
    end
  end
end
