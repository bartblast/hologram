defmodule Hologram.ExJsConsistency.Erlang.ErlangTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erlang_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true
  alias Hologram.Commons.SystemUtils

  @moduletag :consistency

  describe "*/2" do
    test "float * float" do
      assert :erlang.*(2.0, 3.0) === 6.0
    end

    test "float * integer" do
      assert :erlang.*(3.0, 2) === 6.0
    end

    test "integer * float" do
      assert :erlang.*(2, 3.0) === 6.0
    end

    test "integer * integer" do
      assert :erlang.*(2, 3) === 6
    end

    test "raises ArithmeticError if the first argument is not a number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: :a * 1",
                   {:erlang, :*, [:a, 1]}
    end

    test "raises ArithmeticError if the second argument is not a number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: 1 * :a",
                   {:erlang, :*, [1, :a]}
    end
  end

  describe "+/1" do
    test "positive float" do
      assert :erlang.+(1.23) == 1.23
    end

    test "positive integer" do
      assert :erlang.+(123) == 123
    end

    test "negative float" do
      assert :erlang.+(-1.23) == -1.23
    end

    test "negative integer" do
      assert :erlang.+(-123) == -123
    end

    test "0.0 (float)" do
      assert :erlang.+(0.0) == 0.0
    end

    test "0 (integer)" do
      assert :erlang.+(0) == 0
    end

    test "non-number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: +(:abc)",
                   {:erlang, :+, [:abc]}
    end
  end

  describe "+/2" do
    test "float + float" do
      assert :erlang.+(1.0, 2.0) === 3.0
    end

    test "float + integer" do
      assert :erlang.+(1.0, 2) === 3.0
    end

    test "integer + float" do
      assert :erlang.+(1, 2.0) === 3.0
    end

    test "integer + integer" do
      assert :erlang.+(1, 2) === 3
    end

    test "raises ArithmeticError if the first argument is not a number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: :a + 1",
                   {:erlang, :+, [:a, 1]}
    end

    test "raises ArithmeticError if the second argument is not a number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: 1 + :a",
                   {:erlang, :+, [1, :a]}
    end
  end

  describe "++/2" do
    test "concatenates a proper non-empty list and another proper non-empty list" do
      assert :erlang.++([1, 2], [3, 4]) == [1, 2, 3, 4]
    end

    test "concatenates a proper non-empty list and an improper list" do
      assert :erlang.++([1, 2], [3 | 4]) == [1, 2, 3 | 4]
    end

    test "concatenates a proper non-empty list and a term that is not a list" do
      assert :erlang.++([1, 2], 3) == [1, 2 | 3]
    end

    test "first list is empty" do
      assert :erlang.++([], [1, 2]) == [1, 2]
    end

    test "second list is empty" do
      assert :erlang.++([1, 2], []) == [1, 2]
    end

    test "raises ArgumentError if the first argument is not a list" do
      assert_error ArgumentError, "argument error", {:erlang, :++, [:abc, []]}
    end

    test "raises ArgumentError if the first argument is an improper list" do
      assert_error ArgumentError, "argument error", {:erlang, :++, [[1 | 2], []]}
    end
  end

  describe "-/1" do
    test "positive float" do
      assert :erlang.-(1.23) == -1.23
    end

    test "positive integer" do
      assert :erlang.-(123) == -123
    end

    test "negative float" do
      assert :erlang.-(-1.23) == 1.23
    end

    test "negative integer" do
      assert :erlang.-(-123) == 123
    end

    test "0.0 (float)" do
      assert :erlang.-(0.0) == 0.0
    end

    test "0 (integer)" do
      assert :erlang.-(0) == 0
    end

    test "non-number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: -(:abc)",
                   {:erlang, :-, [:abc]}
    end
  end

  describe "-/2" do
    test "float - float" do
      assert :erlang.-(3.0, 2.0) === 1.0
    end

    test "float - integer" do
      assert :erlang.-(3.0, 2) === 1.0
    end

    test "integer - float" do
      assert :erlang.-(3, 2.0) === 1.0
    end

    test "integer - integer" do
      assert :erlang.-(3, 2) === 1
    end

    test "raises ArithmeticError if the first argument is not a number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: :a - 1",
                   {:erlang, :-, [:a, 1]}
    end

    test "raises ArithmeticError if the second argument is not a number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: 1 - :a",
                   {:erlang, :-, [1, :a]}
    end
  end

  describe "--/2" do
    test "there are no matching elems" do
      assert :erlang.--([1, 2], [3, 4]) == [1, 2]
    end

    test "removes the first occurrence of an element in the left list for each element in the right list" do
      assert :erlang.--([1, 2, 3, 1, 2, 3, 1], [1, 3, 3, 4]) == [2, 1, 2, 1]
    end

    test "first list is empty" do
      assert :erlang.--([], [1, 2]) == []
    end

    test "second list is empty" do
      assert :erlang.--([1, 2], []) == [1, 2]
    end

    test "first arg is not a list" do
      assert_error ArgumentError,
                   "argument error",
                   {:erlang, :--, [:abc, [1, 2]]}
    end

    test "second arg is not a list" do
      assert_error ArgumentError,
                   "argument error",
                   {:erlang, :--, [[1, 2], :abc]}
    end
  end

  describe "//2" do
    test "divides float by float" do
      assert :erlang./(3.0, 2.0) == 1.5
    end

    test "divides integer by integer" do
      assert :erlang./(3, 2) == 1.5
    end

    test "first arg is not a number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: :abc / 3",
                   {:erlang, :/, [:abc, 3]}
    end

    test "second arg is not a number" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: 3 / :abc",
                   {:erlang, :/, [3, :abc]}
    end

    test "second arg is equal to (float) 0.0" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: 1 / 0.0",
                   {:erlang, :/, [1, 0.0]}
    end

    test "second arg is equal to (integer) 0" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: 1 / 0",
                   {:erlang, :/, [1, 0]}
    end
  end

  describe "/=/2" do
    test "atom == atom" do
      assert :erlang."/="(:a, :a) == false
    end

    test "float == float" do
      assert :erlang."/="(1.0, 1.0) == false
    end

    test "float == integer" do
      assert :erlang."/="(1.0, 1) == false
    end

    test "integer == float" do
      assert :erlang."/="(1, 1.0) == false
    end

    test "integer == integer" do
      assert :erlang."/="(1, 1) == false
    end

    test "pid == pid" do
      left_pid = pid("0.11.222")
      right_pid = pid("0.11.222")

      assert :erlang."/="(left_pid, right_pid) == false
    end

    test "tuple == tuple" do
      assert :erlang."/="({1, 2, 3}, {1, 2, 3}) == false
    end

    test "atom < atom" do
      assert :erlang."/="(:a, :b) == true
    end

    test "float < atom (always)" do
      assert :erlang."/="(1.0, :a) == true
    end

    test "float < float" do
      assert :erlang."/="(1.0, 2.0) == true
    end

    test "float < integer" do
      assert :erlang."/="(1.0, 2) == true
    end

    test "integer < atom (always)" do
      assert :erlang."/="(1, :a) == true
    end

    test "integer < float" do
      assert :erlang."/="(1, 2.0) == true
    end

    test "integer < integer" do
      assert :erlang."/="(1, 2) == true
    end

    test "pid < pid" do
      left_pid = pid("0.11.111")
      right_pid = pid("0.11.112")

      assert :erlang."/="(left_pid, right_pid) == true
    end

    test "pid < tuple (always)" do
      pid = pid("0.11.111")
      assert :erlang."/="(pid, {1, 2}) == true
    end

    test "tuple < tuple" do
      assert :erlang."/="({1, 2}, {1, 2, 3}) == true
    end

    test "atom > atom" do
      assert :erlang."/="(:b, :a) == true
    end

    test "float > float" do
      assert :erlang."/="(2.0, 1.0) == true
    end

    test "float > integer" do
      assert :erlang."/="(2.0, 1) == true
    end

    test "integer > float" do
      assert :erlang."/="(2, 1.0) == true
    end

    test "integer > integer" do
      assert :erlang."/="(2, 1) == true
    end

    test "pid > pid" do
      left_pid = pid("0.11.112")
      right_pid = pid("0.11.111")

      assert :erlang."/="(left_pid, right_pid) == true
    end

    test "tuple > tuple" do
      assert :erlang."/="({1, 2, 3}, {1, 2}) == true
    end

    # // TODO: reference, function, port, map, list, bitstring
  end

  describe "</2" do
    test "atom == atom" do
      assert :erlang.<(:a, :a) == false
    end

    test "float == float" do
      assert :erlang.<(1.0, 1.0) == false
    end

    test "float == integer" do
      assert :erlang.<(1.0, 1) == false
    end

    test "integer == float" do
      assert :erlang.<(1, 1.0) == false
    end

    test "integer == integer" do
      assert :erlang.<(1, 1) == false
    end

    test "pid == pid" do
      left_pid = pid("0.11.222")
      right_pid = pid("0.11.222")

      assert :erlang.<(left_pid, right_pid) == false
    end

    test "tuple == tuple" do
      assert :erlang.<({1, 2, 3}, {1, 2, 3}) == false
    end

    test "atom < atom" do
      left = wrap_term(:a)
      right = wrap_term(:b)

      assert :erlang.<(left, right) == true
    end

    test "float < atom (always)" do
      left = wrap_term(1.0)
      right = wrap_term(:a)

      assert :erlang.<(left, right) == true
    end

    test "float < float" do
      assert :erlang.<(1.0, 2.0) == true
    end

    test "float < integer" do
      left = wrap_term(1.0)
      right = wrap_term(2)

      assert :erlang.<(left, right) == true
    end

    test "integer < atom (always)" do
      left = wrap_term(1)
      right = wrap_term(:a)

      assert :erlang.<(left, right) == true
    end

    test "integer < float" do
      assert :erlang.<(1, 2.0) == true
    end

    test "integer < integer" do
      assert :erlang.<(1, 2) == true
    end

    test "pid < pid" do
      left_pid = pid("0.11.111")
      right_pid = pid("0.11.112")

      assert :erlang.<(left_pid, right_pid) == true
    end

    test "pid < tuple (always)" do
      pid = pid("0.11.111")
      assert :erlang.<(pid, {1, 2}) == true
    end

    test "tuple < tuple" do
      left = wrap_term({1, 2})
      right = wrap_term({1, 2, 3})

      assert :erlang.<(left, right) == true
    end

    test "atom > atom" do
      left = wrap_term(:b)
      right = wrap_term(:a)

      assert :erlang.<(left, right) == false
    end

    test "float > float" do
      assert :erlang.<(2.0, 1.0) == false
    end

    test "float > integer" do
      assert :erlang.<(2.0, 1) == false
    end

    test "integer > float" do
      assert :erlang.<(2, 1.0) == false
    end

    test "integer > integer" do
      assert :erlang.<(2, 1) == false
    end

    test "pid > pid" do
      left_pid = pid("0.11.112")
      right_pid = pid("0.11.111")

      assert :erlang.<(left_pid, right_pid) == false
    end

    test "tuple > tuple" do
      arg_1 = prevent_term_typing_violation({1, 2, 3})
      arg_2 = prevent_term_typing_violation({1, 2})

      assert :erlang.<(arg_1, arg_2) == false
    end

    # // TODO: reference, function, port, map, list, bitstring
  end

  describe "=/=/2" do
    test "atom == atom" do
      assert :erlang."=/="(:a, :a) == false
    end

    test "float == float" do
      assert :erlang."=/="(1.0, 1.0) == false
    end

    test "float == integer" do
      assert :erlang."=/="(1.0, 1) == true
    end

    test "integer == float" do
      assert :erlang."=/="(1, 1.0) == true
    end

    test "integer == integer" do
      assert :erlang."=/="(1, 1) == false
    end

    test "pid == pid" do
      left_pid = pid("0.11.222")
      right_pid = pid("0.11.222")

      assert :erlang."=/="(left_pid, right_pid) == false
    end

    test "tuple == tuple" do
      assert :erlang."=/="({1, 2, 3}, {1, 2, 3}) == false
    end

    test "atom < atom" do
      assert :erlang."=/="(:a, :b) == true
    end

    test "float < atom (always)" do
      assert :erlang."=/="(1.0, :a) == true
    end

    test "float < float" do
      assert :erlang."=/="(1.0, 2.0) == true
    end

    test "float < integer" do
      assert :erlang."=/="(1.0, 2) == true
    end

    test "integer < atom (always)" do
      assert :erlang."=/="(1, :a) == true
    end

    test "integer < float" do
      assert :erlang."=/="(1, 2.0) == true
    end

    test "integer < integer" do
      assert :erlang."=/="(1, 2) == true
    end

    test "pid < pid" do
      left_pid = pid("0.11.111")
      right_pid = pid("0.11.112")

      assert :erlang."=/="(left_pid, right_pid) == true
    end

    test "pid < tuple (always)" do
      pid = pid("0.11.111")
      assert :erlang."=/="(pid, {1, 2}) == true
    end

    test "tuple < tuple" do
      assert :erlang."=/="({1, 2}, {1, 2, 3}) == true
    end

    test "atom > atom" do
      assert :erlang."=/="(:b, :a) == true
    end

    test "float > float" do
      assert :erlang."=/="(2.0, 1.0) == true
    end

    test "float > integer" do
      assert :erlang."=/="(2.0, 1) == true
    end

    test "integer > float" do
      assert :erlang."=/="(2, 1.0) == true
    end

    test "integer > integer" do
      assert :erlang."=/="(2, 1) == true
    end

    test "pid > pid" do
      left_pid = pid("0.11.112")
      right_pid = pid("0.11.111")

      assert :erlang."=/="(left_pid, right_pid) == true
    end

    test "tuple > tuple" do
      assert :erlang."=/="({1, 2, 3}, {1, 2}) == true
    end

    # // TODO: reference, function, port, map, list, bitstring
  end

  describe "=:=/2" do
    test "atom == atom" do
      assert :erlang."=:="(:a, :a) == true
    end

    test "float == float" do
      assert :erlang."=:="(1.0, 1.0) == true
    end

    test "float == integer" do
      assert :erlang."=:="(1.0, 1) == false
    end

    test "integer == float" do
      assert :erlang."=:="(1, 1.0) == false
    end

    test "integer == integer" do
      assert :erlang."=:="(1, 1) == true
    end

    test "pid == pid" do
      left_pid = pid("0.11.222")
      right_pid = pid("0.11.222")

      assert :erlang."=:="(left_pid, right_pid) == true
    end

    test "tuple == tuple" do
      assert :erlang."=:="({1, 2, 3}, {1, 2, 3}) == true
    end

    test "atom < atom" do
      assert :erlang."=:="(:a, :b) == false
    end

    test "float < atom (always)" do
      assert :erlang."=:="(1.0, :a) == false
    end

    test "float < float" do
      assert :erlang."=:="(1.0, 2.0) == false
    end

    test "float < integer" do
      assert :erlang."=:="(1.0, 2) == false
    end

    test "integer < atom (always)" do
      assert :erlang."=:="(1, :a) == false
    end

    test "integer < float" do
      assert :erlang."=:="(1, 2.0) == false
    end

    test "integer < integer" do
      assert :erlang."=:="(1, 2) == false
    end

    test "pid < pid" do
      left_pid = pid("0.11.111")
      right_pid = pid("0.11.112")

      assert :erlang."=:="(left_pid, right_pid) == false
    end

    test "pid < tuple (always)" do
      pid = pid("0.11.111")
      assert :erlang."=:="(pid, {1, 2}) == false
    end

    test "tuple < tuple" do
      assert :erlang."=:="({1, 2}, {1, 2, 3}) == false
    end

    test "atom > atom" do
      assert :erlang."=:="(:b, :a) == false
    end

    test "float > float" do
      assert :erlang."=:="(2.0, 1.0) == false
    end

    test "float > integer" do
      assert :erlang."=:="(2.0, 1) == false
    end

    test "integer > float" do
      assert :erlang."=:="(2, 1.0) == false
    end

    test "integer > integer" do
      assert :erlang."=:="(2, 1) == false
    end

    test "pid > pid" do
      left_pid = pid("0.11.112")
      right_pid = pid("0.11.111")

      assert :erlang."=:="(left_pid, right_pid) == false
    end

    test "tuple > tuple" do
      assert :erlang."=:="({1, 2, 3}, {1, 2}) == false
    end

    # // TODO: reference, function, port, map, list, bitstring
  end

  describe "=</2" do
    test "atom == atom" do
      assert :erlang."=<"(:a, :a) == true
    end

    test "float == float" do
      assert :erlang."=<"(1.0, 1.0) == true
    end

    test "float == integer" do
      assert :erlang."=<"(1.0, 1) == true
    end

    test "integer == float" do
      assert :erlang."=<"(1, 1.0) == true
    end

    test "integer == integer" do
      assert :erlang."=<"(1, 1) == true
    end

    test "pid == pid" do
      left_pid = pid("0.11.222")
      right_pid = pid("0.11.222")

      assert :erlang."=<"(left_pid, right_pid) == true
    end

    test "tuple == tuple" do
      assert :erlang."=<"({1, 2, 3}, {1, 2, 3}) == true
    end

    test "atom < atom" do
      left = wrap_term(:a)
      right = wrap_term(:b)

      assert :erlang."=<"(left, right) == true
    end

    test "float < atom (always)" do
      left = wrap_term(1.0)
      right = wrap_term(:a)

      assert :erlang."=<"(left, right) == true
    end

    test "float < float" do
      assert :erlang."=<"(1.0, 2.0) == true
    end

    test "float < integer" do
      assert :erlang."=<"(1.0, 2) == true
    end

    test "integer < atom (always)" do
      left = wrap_term(1)
      right = wrap_term(:a)

      assert :erlang."=<"(left, right) == true
    end

    test "integer < float" do
      assert :erlang."=<"(1, 2.0) == true
    end

    test "integer < integer" do
      assert :erlang."=<"(1, 2) == true
    end

    test "pid < pid" do
      left_pid = pid("0.11.111")
      right_pid = pid("0.11.112")

      assert :erlang."=<"(left_pid, right_pid) == true
    end

    test "pid < tuple (always)" do
      pid = pid("0.11.111")
      assert :erlang."=<"(pid, {1, 2}) == true
    end

    test "tuple < tuple" do
      arg_1 = prevent_term_typing_violation({1, 2})
      arg_2 = prevent_term_typing_violation({1, 2, 3})

      assert :erlang."=<"(arg_1, arg_2) == true
    end

    test "atom > atom" do
      left = wrap_term(:b)
      right = wrap_term(:a)

      assert :erlang."=<"(left, right) == false
    end

    test "float > float" do
      assert :erlang."=<"(2.0, 1.0) == false
    end

    test "float > integer" do
      assert :erlang."=<"(2.0, 1) == false
    end

    test "integer > float" do
      assert :erlang."=<"(2, 1.0) == false
    end

    test "integer > integer" do
      assert :erlang."=<"(2, 1) == false
    end

    test "pid > pid" do
      left_pid = pid("0.11.112")
      right_pid = pid("0.11.111")

      assert :erlang."=<"(left_pid, right_pid) == false
    end

    test "tuple > tuple" do
      arg_1 = prevent_term_typing_violation({1, 2, 3})
      arg_2 = prevent_term_typing_violation({1, 2})

      assert :erlang."=<"(arg_1, arg_2) == false
    end

    # // TODO: reference, function, port, map, list, bitstring
  end

  describe "==/2" do
    test "atom == atom" do
      assert :erlang.==(:a, :a) == true
    end

    test "float == float" do
      assert :erlang.==(1.0, 1.0) == true
    end

    test "float == integer" do
      assert :erlang.==(1.0, 1) == true
    end

    test "integer == float" do
      assert :erlang.==(1, 1.0) == true
    end

    test "integer == integer" do
      assert :erlang.==(1, 1) == true
    end

    test "pid == pid" do
      left_pid = pid("0.11.222")
      right_pid = pid("0.11.222")

      assert :erlang.==(left_pid, right_pid) == true
    end

    test "tuple == tuple" do
      assert :erlang.==({1, 2, 3}, {1, 2, 3}) == true
    end

    test "atom < atom" do
      assert :erlang.==(:a, :b) == false
    end

    test "float < atom (always)" do
      assert :erlang.==(1.0, :a) == false
    end

    test "float < float" do
      assert :erlang.==(1.0, 2.0) == false
    end

    test "float < integer" do
      assert :erlang.==(1.0, 2) == false
    end

    test "integer < atom (always)" do
      assert :erlang.==(1, :a) == false
    end

    test "integer < float" do
      assert :erlang.==(1, 2.0) == false
    end

    test "integer < integer" do
      assert :erlang.==(1, 2) == false
    end

    test "pid < pid" do
      left_pid = pid("0.11.111")
      right_pid = pid("0.11.112")

      assert :erlang.==(left_pid, right_pid) == false
    end

    test "pid < tuple (always)" do
      pid = pid("0.11.111")
      assert :erlang.==(pid, {1, 2}) == false
    end

    test "tuple < tuple" do
      assert :erlang.==({1, 2}, {1, 2, 3}) == false
    end

    test "atom > atom" do
      assert :erlang.==(:b, :a) == false
    end

    test "float > float" do
      assert :erlang.==(2.0, 1.0) == false
    end

    test "float > integer" do
      assert :erlang.==(2.0, 1) == false
    end

    test "integer > float" do
      assert :erlang.==(2, 1.0) == false
    end

    test "integer > integer" do
      assert :erlang.==(2, 1) == false
    end

    test "pid > pid" do
      left_pid = pid("0.11.112")
      right_pid = pid("0.11.111")

      assert :erlang.==(left_pid, right_pid) == false
    end

    test "tuple > tuple" do
      assert :erlang.==({1, 2, 3}, {1, 2}) == false
    end

    # // TODO: reference, function, port, map, list, bitstring
  end

  describe ">/2" do
    test "atom == atom" do
      assert :erlang.>(:a, :a) == false
    end

    test "float == float" do
      assert :erlang.>(1.0, 1.0) == false
    end

    test "float == integer" do
      assert :erlang.>(1.0, 1) == false
    end

    test "integer == float" do
      assert :erlang.>(1, 1.0) == false
    end

    test "integer == integer" do
      assert :erlang.>(1, 1) == false
    end

    test "pid == pid" do
      left_pid = pid("0.11.222")
      right_pid = pid("0.11.222")

      assert :erlang.>(left_pid, right_pid) == false
    end

    test "tuple == tuple" do
      assert :erlang.>({1, 2, 3}, {1, 2, 3}) == false
    end

    test "atom < atom" do
      left = wrap_term(:a)
      right = wrap_term(:b)

      assert :erlang.>(left, right) == false
    end

    test "float < atom (always)" do
      left = wrap_term(1.0)
      right = wrap_term(:a)

      assert :erlang.>(left, right) == false
    end

    test "float < float" do
      assert :erlang.>(1.0, 2.0) == false
    end

    test "float < integer" do
      assert :erlang.>(1.0, 2) == false
    end

    test "integer < atom (always)" do
      left = wrap_term(1)
      right = wrap_term(:a)

      assert :erlang.>(left, right) == false
    end

    test "integer < float" do
      assert :erlang.>(1, 2.0) == false
    end

    test "integer < integer" do
      assert :erlang.>(1, 2) == false
    end

    test "pid < pid" do
      left_pid = pid("0.11.111")
      right_pid = pid("0.11.112")

      assert :erlang.>(left_pid, right_pid) == false
    end

    test "pid < tuple (always)" do
      pid = pid("0.11.111")
      assert :erlang.>(pid, {1, 2}) == false
    end

    test "tuple < tuple" do
      arg_1 = prevent_term_typing_violation({1, 2})
      arg_2 = prevent_term_typing_violation({1, 2, 3})

      assert :erlang.>(arg_1, arg_2) == false
    end

    test "atom > atom" do
      left = wrap_term(:b)
      right = wrap_term(:a)

      assert :erlang.>(left, right) == true
    end

    test "float > float" do
      assert :erlang.>(2.0, 1.0) == true
    end

    test "float > integer" do
      assert :erlang.>(2.0, 1) == true
    end

    test "integer > float" do
      assert :erlang.>(2, 1.0) == true
    end

    test "integer > integer" do
      assert :erlang.>(2, 1) == true
    end

    test "pid > pid" do
      left_pid = pid("0.11.112")
      right_pid = pid("0.11.111")

      assert :erlang.>(left_pid, right_pid) == true
    end

    test "tuple > tuple" do
      arg_1 = prevent_term_typing_violation({1, 2, 3})
      arg_2 = prevent_term_typing_violation({1, 2})

      assert :erlang.>(arg_1, arg_2) == true
    end

    # // TODO: reference, function, port, map, list, bitstring
  end

  describe ">=/2" do
    test "atom == atom" do
      assert :erlang.>=(:a, :a) == true
    end

    test "float == float" do
      assert :erlang.>=(1.0, 1.0) == true
    end

    test "float == integer" do
      assert :erlang.>=(1.0, 1) == true
    end

    test "integer == float" do
      assert :erlang.>=(1, 1.0) == true
    end

    test "integer == integer" do
      assert :erlang.>=(1, 1) == true
    end

    test "pid == pid" do
      left_pid = pid("0.11.222")
      right_pid = pid("0.11.222")

      assert :erlang.>=(left_pid, right_pid) == true
    end

    test "tuple == tuple" do
      assert :erlang.>=({1, 2, 3}, {1, 2, 3}) == true
    end

    test "atom < atom" do
      left = wrap_term(:a)
      right = wrap_term(:b)

      assert :erlang.>=(left, right) == false
    end

    test "float < atom (always)" do
      left = wrap_term(1.0)
      right = wrap_term(:a)

      assert :erlang.>=(left, right) == false
    end

    test "float < float" do
      assert :erlang.>=(1.0, 2.0) == false
    end

    test "float < integer" do
      assert :erlang.>=(1.0, 2) == false
    end

    test "integer < atom (always)" do
      left = wrap_term(1)
      right = wrap_term(:a)

      assert :erlang.>=(left, right) == false
    end

    test "integer < float" do
      assert :erlang.>=(1, 2.0) == false
    end

    test "integer < integer" do
      assert :erlang.>=(1, 2) == false
    end

    test "pid < pid" do
      left_pid = pid("0.11.111")
      right_pid = pid("0.11.112")

      assert :erlang.>=(left_pid, right_pid) == false
    end

    test "pid < tuple (always)" do
      pid = pid("0.11.111")
      assert :erlang.>=(pid, {1, 2}) == false
    end

    test "tuple < tuple" do
      arg_1 = prevent_term_typing_violation({1, 2})
      arg_2 = prevent_term_typing_violation({1, 2, 3})

      assert :erlang.>=(arg_1, arg_2) == false
    end

    test "atom > atom" do
      left = wrap_term(:b)
      right = wrap_term(:a)

      assert :erlang.>=(left, right) == true
    end

    test "float > float" do
      assert :erlang.>=(2.0, 1.0) == true
    end

    test "float > integer" do
      assert :erlang.>=(2.0, 1) == true
    end

    test "integer > float" do
      assert :erlang.>=(2, 1.0) == true
    end

    test "integer > integer" do
      assert :erlang.>=(2, 1) == true
    end

    test "pid > pid" do
      left_pid = pid("0.11.112")
      right_pid = pid("0.11.111")

      assert :erlang.>=(left_pid, right_pid) == true
    end

    test "tuple > tuple" do
      arg_1 = prevent_term_typing_violation({1, 2, 3})
      arg_2 = prevent_term_typing_violation({1, 2})

      assert :erlang.>=(arg_1, arg_2) == true
    end

    # // TODO: reference, function, port, map, list, bitstring
  end

  describe "abs/1" do
    test "positive float" do
      assert :erlang.abs(1.23) == 1.23
    end

    test "negative float" do
      assert :erlang.abs(-1.23) == 1.23
    end

    test "zero float" do
      assert :erlang.abs(0.0) == 0.0
    end

    test "positive integer" do
      assert :erlang.abs(123) == 123
    end

    test "negative integer" do
      assert :erlang.abs(-123) == 123
    end

    test "zero integer" do
      assert :erlang.abs(0) == 0
    end

    test "large positive integer" do
      assert :erlang.abs(123_456_789_012_345_678_901_234_567_890) ==
               123_456_789_012_345_678_901_234_567_890
    end

    test "large negative integer" do
      assert :erlang.abs(-123_456_789_012_345_678_901_234_567_890) ==
               123_456_789_012_345_678_901_234_567_890
    end

    test "raises ArgumentError if the argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:erlang, :abs, [:abc]}
    end
  end

  describe "andalso/2" do
    test "returns false if the first argument is false" do
      assert :erlang.andalso(false, :abc) == false
    end

    test "returns the second argument if the first argument is true" do
      assert :erlang.andalso(true, :abc) == :abc
    end

    test "doesn't evaluate the second argument if the first argument is false" do
      assert :erlang.andalso(false, apply(:impossible, [])) == false
    end

    test "raises ArgumentError if the first argument is not a boolean" do
      arg = prevent_term_typing_violation(nil)

      assert_error ArgumentError,
                   "argument error: nil",
                   fn -> :erlang.andalso(arg, true) end
    end
  end

  if SystemUtils.otp_version() >= 23 do
    describe "atom_to_binary/1" do
      test "delegates to atom_to_binary/2" do
        assert :erlang.atom_to_binary(:全息图) == :erlang.atom_to_binary(:全息图, :utf8)
      end
    end
  end

  describe "atom_to_binary/2" do
    test "utf8 encoding" do
      assert :erlang.atom_to_binary(:全息图, :utf8) == "全息图"
    end

    test "raises ArgumentError if the first arg is not an atom" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an atom"),
                   {:erlang, :atom_to_binary, [123, :utf8]}
    end
  end

  describe "atom_to_list/1" do
    test "empty atom" do
      assert :erlang.atom_to_list(:"") == []
    end

    test "ASCII atom" do
      assert :erlang.atom_to_list(:abc) == [97, 98, 99]
    end

    test "Unicode atom" do
      assert :erlang.atom_to_list(:全息图) == [20_840, 24_687, 22_270]
    end

    test "not an atom" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an atom"),
                   {:erlang, :atom_to_list, [123]}
    end
  end

  if SystemUtils.otp_version() >= 23 do
    test "binary_to_atom/1" do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      assert :erlang.binary_to_atom("全息图") == :erlang.binary_to_atom("全息图", :utf8)
    end
  end

  describe "binary_to_atom/2" do
    test "converts a binary bitstring to an already existing atom" do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      assert :erlang.binary_to_atom("Elixir.Kernel", :utf8) == Kernel
    end

    test "converts a binary bitstring to a not existing yet atom" do
      random_str = inspect(make_ref())

      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      result = :erlang.binary_to_atom(random_str, :utf8)

      assert to_string(result) == random_str
    end

    test "raises ArgumentError if the first argument is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_to_atom, [<<1::1, 0::1, 1::1>>, :utf8]}
    end

    test "raises ArgumentErorr if the first argument is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_to_atom, [:abc, :utf8]}
    end
  end

  # Note: due to practical reasons the behaviour of the client version is inconsistent with the server version.
  # The client version works exactly the same as binary_to_atom/1.
  # test "binary_to_existing_atoms/1"

  # Note: due to practical reasons the behaviour of the client version is inconsistent with the server version.
  # The client version works exactly the same as binary_to_atom/2.
  # test "binary_to_existing_atom/2"

  describe "binary_to_integer/1" do
    test "delegates to binary_to_integer/2 with base 10" do
      assert :erlang.binary_to_integer("123") == :erlang.binary_to_integer("123", 10)
    end
  end

  describe "binary_to_integer/2" do
    test "base 2" do
      assert :erlang.binary_to_integer("1111", 2) == 15
    end

    test "base 8" do
      assert :erlang.binary_to_integer("177", 8) == 127
    end

    test "base 10" do
      assert :erlang.binary_to_integer("123", 10) == 123
    end

    test "base 16" do
      assert :erlang.binary_to_integer("3FF", 16) == 1023
    end

    test "base 36" do
      assert :erlang.binary_to_integer("ZZ", 36) == 1295
    end

    test "positive integer without sign" do
      assert :erlang.binary_to_integer("123", 10) == 123
    end

    test "positive integer with plus sign" do
      assert :erlang.binary_to_integer("+123", 10) == 123
    end

    test "negative integer" do
      assert :erlang.binary_to_integer("-123", 10) == -123
    end

    test "zero" do
      assert :erlang.binary_to_integer("0", 10) == 0
    end

    test "positive zero" do
      assert :erlang.binary_to_integer("+0", 10) == 0
    end

    test "negative zero" do
      assert :erlang.binary_to_integer("-0", 10) == 0
    end

    test "lowercase letters" do
      assert :erlang.binary_to_integer("abcd", 16) == 43_981
    end

    test "uppercase letters" do
      assert :erlang.binary_to_integer("ABCD", 16) == 43_981
    end

    test "mixed case letters" do
      assert :erlang.binary_to_integer("aBcD", 16) == 43_981
    end

    test "raises ArgumentError if the first argument is not a binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_to_integer, [:abc, 10]}
    end

    test "raises ArgumentError if the first argument is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_to_integer, [<<5::size(3)>>, 10]}
    end

    test "raises ArgumentError if binary is empty" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   {:erlang, :binary_to_integer, ["", 10]}
    end

    test "raises ArgumentError if binary contains characters outside of the alphabet" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   {:erlang, :binary_to_integer, ["123", 2]}
    end

    test "raises ArgumentError if the second argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :binary_to_integer, ["123", :abc]}
    end

    test "raises ArgumentError if base is less than 2" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :binary_to_integer, ["123", 1]}
    end

    test "raises ArgumentError if base is greater than 36" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :binary_to_integer, ["123", 37]}
    end
  end

  describe "bit_size/1" do
    test "bitstring" do
      assert :erlang.bit_size(<<2::7>>) == 7
    end

    test "not bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a bitstring"),
                   {:erlang, :bit_size, [:abc]}
    end
  end

  describe "byte_size/1" do
    test "empty bitstring" do
      assert :erlang.byte_size("") == 0
    end

    test "binary bitstring" do
      assert :erlang.byte_size("abc") == 3
    end

    test "non-binary bitstring" do
      bitstring = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>
      assert :erlang.byte_size(bitstring) == 2
    end

    test "not bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a bitstring"),
                   {:erlang, :byte_size, [:abc]}
    end
  end

  describe "div/2" do
    test "divides positive integers" do
      assert :erlang.div(10, 3) === 3
    end

    test "divides negative dividend by positive divisor" do
      assert :erlang.div(-10, 3) === -3
    end

    test "divides positive dividend by negative divisor" do
      assert :erlang.div(10, -3) === -3
    end

    test "divides negative integers" do
      assert :erlang.div(-10, -3) === 3
    end

    test "divides evenly" do
      assert :erlang.div(12, 4) === 3
    end

    test "truncates toward zero for positive result" do
      assert :erlang.div(7, 2) === 3
    end

    test "truncates toward zero for negative result" do
      assert :erlang.div(-7, 2) === -3
    end

    test "divides by 1" do
      assert :erlang.div(42, 1) === 42
    end

    test "divides by -1" do
      assert :erlang.div(42, -1) === -42
    end

    test "divides 0 by non-zero" do
      assert :erlang.div(0, 5) === 0
    end

    test "raises ArithmeticError when dividing by zero" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: div(5, 0)", fn ->
        assert :erlang.div(5, 0)
      end
    end

    test "raises ArgumentError if the first argument is a float" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: div(5.5, 2)", fn ->
        assert :erlang.div(5.5, 2)
      end
    end

    test "raises ArgumentError if the second argument is a float" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: div(5, 2.5)", fn ->
        assert :erlang.div(5, 2.5)
      end
    end

    test "raises ArgumentError if the first argument is not a number" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: div(:abc, 2)", fn ->
        assert :erlang.div(:abc, 2)
      end
    end

    test "raises ArgumentError if the second argument is not a number" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: div(5, :abc)", fn ->
        assert :erlang.div(5, :abc)
      end
    end
  end

  describe "display/1" do
    test "displays an atom and returns :ok" do
      assert :erlang.display(:hello) == :ok
    end

    test "displays an integer and returns :ok" do
      assert :erlang.display(42) == :ok
    end

    test "displays a list and returns :ok" do
      assert :erlang.display([1, 2, 3]) == :ok
    end

    test "displays a tuple and returns :ok" do
      assert :erlang.display({:a, :b}) == :ok
    end
  end

  describe "element/2" do
    test "returns the element at the one-based index in the tuple" do
      assert :erlang.element(2, {5, 6, 7}) == 6
    end

    test "raises ArgumentError if the first argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an integer"),
                   {:erlang, :element, [:abc, {5, 6, 7}]}
    end

    test "raises ArgumentError if the second argument is not a tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a tuple"),
                   {:erlang, :element, [1, :abc]}
    end

    test "raises ArgumentError if the given index is greater than the number of elements in the tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "out of range"),
                   {:erlang, :element, [10, {5, 6, 7}]}
    end

    test "raises ArgumentError if the given index is smaller than 1" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "out of range"),
                   {:erlang, :element, [0, {5, 6, 7}]}
    end
  end

  describe "float/1" do
    test "converts integer to float" do
      assert :erlang.float(42) === 42.0
    end

    test "returns float unchanged" do
      assert :erlang.float(3.14) === 3.14
    end

    test "converts zero integer to float" do
      assert :erlang.float(0) === 0.0
    end

    test "raises ArgumentError if argument is not a number" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a number"), fn ->
        :erlang.float(:not_a_number)
      end
    end
  end

  describe "float_to_binary/2" do
    test ":short option" do
      assert :erlang.float_to_binary(0.1 + 0.2, [:short]) == "0.30000000000000004"
    end

    test "raises ArgumentError if the first argument is not a float" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a float"), fn ->
        :erlang.float_to_binary(123, [:short])
      end
    end

    test "raises ArgumentError if the second argument is not a list" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a list"), fn ->
        :erlang.float_to_binary(1.0, 123)
      end
    end

    test "raises ArgumentError if the second argument is not a proper list" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a proper list"), fn ->
        :erlang.float_to_binary(1.0, [{:decimals, 4} | :compact])
      end
    end
  end

  describe "function_exported/3" do
    test "returns true if function is exported" do
      assert :erlang.function_exported(Kernel, :+, 2) == true
    end

    test "returns false if function is not exported" do
      assert :erlang.function_exported(Kernel, :non_existent, 0) == false
    end

    test "returns false if module does not exist" do
      assert :erlang.function_exported(NonExistentModule, :foo, 1) == false
    end

    test "raises ArgumentError if first argument is not an atom" do
      assert_error ArgumentError, build_argument_error_msg(1, "not an atom"), fn ->
        :erlang.function_exported(123, :foo, 1)
      end
    end

    test "raises ArgumentError if second argument is not an atom" do
      assert_error ArgumentError, build_argument_error_msg(2, "not an atom"), fn ->
        :erlang.function_exported(Kernel, 123, 1)
      end
    end

    test "raises ArgumentError if third argument is not an integer" do
      assert_error ArgumentError, build_argument_error_msg(3, "not an integer"), fn ->
        :erlang.function_exported(Kernel, :+, :not_an_integer)
      end
    end
  end

  describe "hd/1" do
    test "returns the first item in the list" do
      assert :erlang.hd([1, 2, 3]) === 1
    end

    test "raises ArgumentError if the argument is an empty list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a nonempty list"),
                   {:erlang, :hd, [[]]}
    end

    test "raises ArgumentError if the argument is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a nonempty list"),
                   {:erlang, :hd, [123]}
    end
  end

  describe "integer_to_binary/1" do
    assert :erlang.integer_to_binary(123_123) == :erlang.integer_to_binary(123_123, 10)
  end

  describe "integer_to_binary/2" do
    test "positive integer, base = 1" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :integer_to_binary, [123_123, 1]}
    end

    test "positive integer, base = 2" do
      assert :erlang.integer_to_binary(123_123, 2) == "11110000011110011"
    end

    test "positive integer, base = 16" do
      assert :erlang.integer_to_binary(123_123, 16) == "1E0F3"
    end

    test "positive integer, base = 36" do
      assert :erlang.integer_to_binary(123_123, 36) == "2N03"
    end

    test "positive integer, base = 37" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :integer_to_binary, [123_123, 37]}
    end

    test "negative integer" do
      assert :erlang.integer_to_binary(-123_123, 16) == "-1E0F3"
    end

    test "1st argument (integer) is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an integer"),
                   {:erlang, :integer_to_binary, [:abc, 16]}
    end

    test "2nd argument (base) is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :integer_to_binary, [123_123, :abc]}
    end
  end

  describe "iolist_to_list/1" do
    test "converts binary to list of bytes" do
      assert :erlang.iolist_to_list("abc") == [97, 98, 99]
    end

    test "converts simple iolist to list of bytes" do
      assert :erlang.iolist_to_list([97, 98, 99]) == [97, 98, 99]
    end

    test "converts nested iolist to list of bytes" do
      assert :erlang.iolist_to_list([97, [98], [[99]]]) == [97, 98, 99]
    end

    test "converts mixed iolist with binaries and integers" do
      assert :erlang.iolist_to_list([97, "bc", 100]) == [97, 98, 99, 100]
    end

    test "raises ArgumentError for integer out of byte range" do
      assert_error ArgumentError, build_argument_error_msg(1, "not an iolist term"), fn ->
        :erlang.iolist_to_list([256])
      end
    end

    test "raises ArgumentError for negative integer" do
      assert_error ArgumentError, build_argument_error_msg(1, "not an iolist term"), fn ->
        :erlang.iolist_to_list([-1])
      end
    end
  end

  describe "is_atom/1" do
    test "atom" do
      assert :erlang.is_atom(:abc) == true
    end

    test "non-atom" do
      assert :erlang.is_atom(123) == false
    end
  end

  describe "is_binary/1" do
    test "binary bitsting" do
      assert :erlang.is_binary("abc") == true
    end

    test "non-binary bitstring" do
      assert :erlang.is_binary(<<2::size(3)>>) == false
    end

    test "non-bitstring" do
      assert :erlang.is_binary(:abc) == false
    end
  end

  describe "is_bitstring/1" do
    test "bitstring" do
      assert :erlang.is_bitstring(<<2::size(3)>>) == true
    end

    test "non-bitstring" do
      assert :erlang.is_bitstring(:abc) == false
    end
  end

  describe "is_boolean/1" do
    test "boolean" do
      assert :erlang.is_boolean(true) == true
    end

    test "non-boolean" do
      assert :erlang.is_boolean(nil) == false
    end
  end

  describe "is_float/1" do
    test "float" do
      assert :erlang.is_float(1.0) == true
    end

    test "non-float" do
      assert :erlang.is_float(:abc) == false
    end
  end

  describe "is_function/1" do
    test "function" do
      assert :erlang.is_function(fn x -> x end) == true
    end

    test "non-function" do
      assert :erlang.is_function(:abc) == false
    end
  end

  describe "is_function/2" do
    test "function with the given arity" do
      term = fn x, y, z -> {x, y, z} end
      assert :erlang.is_function(term, 3) == true
    end

    test "function with a different arity" do
      term = fn x, y, z -> {x, y, z} end
      assert :erlang.is_function(term, 4) == false
    end

    test "non-function" do
      assert :erlang.is_function(:abc, 3) == false
    end
  end

  describe "is_integer/1" do
    test "integer" do
      assert :erlang.is_integer(1) == true
    end

    test "non-integer" do
      assert :erlang.is_integer(:abc) == false
    end
  end

  describe "is_list/1" do
    test "list" do
      assert :erlang.is_list([1, 2]) == true
    end

    test "non-list" do
      assert :erlang.is_list(:abc) == false
    end
  end

  describe "is_map/1" do
    test "map" do
      assert :erlang.is_map(%{a: 1, b: 2}) == true
    end

    test "non-map" do
      assert :erlang.is_map(:abc) == false
    end
  end

  describe "is_number/1" do
    test "float" do
      assert :erlang.is_number(1.0) == true
    end

    test "integer" do
      assert :erlang.is_number(1) == true
    end

    test "non-number" do
      assert :erlang.is_number(:abc) == false
    end
  end

  describe "is_pid/1" do
    test "pid" do
      assert :erlang.is_pid(self()) == true
    end

    test "non-pid" do
      assert :erlang.is_pid(:abc) == false
    end
  end

  describe "is_port/1" do
    test "port" do
      port = port("0.11")
      assert :erlang.is_port(port) == true
    end

    test "non-port" do
      assert :erlang.is_port(:abc) == false
    end
  end

  describe "is_reference/1" do
    test "reference" do
      assert :erlang.is_reference(make_ref()) == true
    end

    test "non-reference" do
      assert :erlang.is_reference(:abc) == false
    end
  end

  describe "is_tuple/1" do
    test "tuple" do
      assert :erlang.is_tuple({1, 2}) == true
    end

    test "non-tuple" do
      assert :erlang.is_tuple(:abc) == false
    end
  end

  describe "length/1" do
    test "returns the number of items in the list" do
      assert :erlang.length([1, 2]) == 2
    end

    test "raises ArgumentError if the argument is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   {:erlang, :length, [:abc]}
    end
  end

  describe "list_to_atom/1" do
    test "converts list of codepoints to atom" do
      assert :erlang.list_to_atom([104, 101, 108, 108, 111]) == :hello
    end

    test "converts empty list to empty atom" do
      assert :erlang.list_to_atom([]) == :""
    end

    test "raises ArgumentError if not a list" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a list"), fn ->
        :erlang.list_to_atom(:not_a_list)
      end
    end

    test "raises ArgumentError if not a proper list" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a proper list"), fn ->
        :erlang.list_to_atom([104 | 101])
      end
    end
  end

  describe "list_to_binary/1" do
    test "converts list of bytes to binary" do
      assert :erlang.list_to_binary([72, 105]) == "Hi"
    end

    test "converts nested iolist to binary" do
      assert :erlang.list_to_binary([72, [105]]) == "Hi"
    end
  end

  describe "list_to_float/1" do
    test "converts list of codepoints to float" do
      assert :erlang.list_to_float([51, 46, 49, 52]) == 3.14
    end

    test "converts negative float" do
      assert :erlang.list_to_float([45, 49, 46, 53]) == -1.5
    end

    test "converts scientific notation" do
      assert :erlang.list_to_float([49, 46, 50, 51, 101, 50]) == 123.0
    end

    test "raises ArgumentError if not a list" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a list"), fn ->
        :erlang.list_to_float(:not_a_list)
      end
    end

    test "raises ArgumentError if not a textual representation of a float" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   fn ->
                     :erlang.list_to_float([49, 50, 51])
                   end
    end
  end

  describe "list_to_integer/1" do
    test "converts list of codepoints to integer" do
      assert :erlang.list_to_integer([49, 50, 51]) == 123
    end

    test "converts negative integer" do
      assert :erlang.list_to_integer([45, 49, 50, 51]) == -123
    end

    test "raises ArgumentError if not a list" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a list"), fn ->
        :erlang.list_to_integer(:not_a_list)
      end
    end

    test "raises ArgumentError if not a textual representation of an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   fn ->
                     :erlang.list_to_integer([49, 46, 50])
                   end
    end
  end

  describe "list_to_tuple/1" do
    test "converts list to tuple" do
      assert :erlang.list_to_tuple([1, 2, 3]) == {1, 2, 3}
    end

    test "converts empty list to empty tuple" do
      assert :erlang.list_to_tuple([]) == {}
    end

    test "raises ArgumentError if not a list" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a list"), fn ->
        :erlang.list_to_tuple(:not_a_list)
      end
    end

    test "raises ArgumentError if not a proper list" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a proper list"), fn ->
        :erlang.list_to_tuple([1 | 2])
      end
    end
  end

  describe "list_to_pid/1" do
    test "valid textual representation of PID" do
      assert :erlang.list_to_pid(~c"<0.11.222>") == pid("0.11.222")
    end

    test "invalid textual representation of PID" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a pid"),
                   {:erlang, :list_to_pid, [~c"<0.11>"]}
    end

    test "not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   {:erlang, :list_to_pid, [123]}
    end

    test "a list that contains a non-integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a pid"),
                   {:erlang, :list_to_pid, [[60, :abc, 46]]}
    end

    test "a list that contains an invalid codepoint" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a pid"),
                   {:erlang, :list_to_pid, [[60, 255, 46]]}
    end
  end

  describe "map_size/1" do
    test "returns the number of items in the map" do
      assert :erlang.map_size(%{a: 1, b: 2}) == 2
    end

    test "raises BadMapError if the argument is not a map" do
      assert_error BadMapError,
                   "expected a map, got: :abc",
                   {:erlang, :map_size, [:abc]}
    end
  end

  describe "not/1" do
    test "true" do
      assert :erlang.not(true) == false
    end

    test "false" do
      assert :erlang.not(false) == true
    end

    test "not boolean" do
      assert_error ArgumentError,
                   "argument error",
                   {:erlang, :not, ["abc"]}
    end
  end

  describe "orelse/2" do
    test "returns true if the first argument is true" do
      assert :erlang.orelse(true, :abc) == true
    end

    test "returns the second argument if the first argument is false" do
      assert :erlang.orelse(false, :abc) == :abc
    end

    test "doesn't evaluate the second argument if the first argument is true" do
      assert :erlang.orelse(true, apply(:impossible, [])) == true
    end

    test "raises ArgumentError if the first argument is not a boolean" do
      arg = prevent_term_typing_violation(nil)

      assert_error ArgumentError,
                   "argument error: nil",
                   fn -> :erlang.orelse(arg, true) end
    end
  end

  describe "rem/2" do
    test "returns remainder of positive integers" do
      assert :erlang.rem(10, 3) === 1
    end

    test "returns remainder with negative dividend and positive divisor" do
      assert :erlang.rem(-10, 3) === -1
    end

    test "returns remainder with positive dividend and negative divisor" do
      assert :erlang.rem(10, -3) === 1
    end

    test "returns remainder with negative integers" do
      assert :erlang.rem(-10, -3) === -1
    end

    test "returns 0 when dividend is evenly divisible" do
      assert :erlang.rem(12, 4) === 0
    end

    test "returns 0 when dividend is 0" do
      assert :erlang.rem(0, 5) === 0
    end

    test "returns 0 when dividend is 1" do
      assert :erlang.rem(42, 1) === 0
    end

    test "returns 0 when dividend is -1" do
      assert :erlang.rem(42, -1) === 0
    end

    test "raises ArithmeticError when dividend is 0" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: rem(5, 0)", fn ->
        assert :erlang.rem(5, 0)
      end
    end

    test "raises ArithmeticError if the first argument is a float" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: rem(5.5, 2)", fn ->
        assert :erlang.rem(5.5, 2)
      end
    end

    test "raises ArithmeticError if the second argument is a float" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: rem(5, 2.5)", fn ->
        assert :erlang.rem(5, 2.5)
      end
    end

    test "raises ArithmeticError if the first argument is not a number" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: rem(:abc, 2)", fn ->
        assert :erlang.rem(:abc, 2)
      end
    end

    test "raises ArithmeticError if the second argument is not a number" do
      assert_error ArithmeticError, "bad argument in arithmetic expression: rem(5, :abc)", fn ->
        assert :erlang.rem(5, :abc)
      end
    end
  end

  describe "round/1" do
    test "rounds float to nearest integer" do
      assert :erlang.round(3.6) == 4
    end

    test "rounds float down" do
      assert :erlang.round(3.4) == 3
    end

    test "rounds exactly half up" do
      assert :erlang.round(2.5) == 3
    end

    test "rounds negative float" do
      assert :erlang.round(-2.7) == -3
    end

    test "returns integer unchanged" do
      assert :erlang.round(42) == 42
    end

    test "raises ArgumentError if not a number" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a number"), fn ->
        :erlang.round(:not_a_number)
      end
    end
  end

  describe "self/0" do
    test "returns a PID" do
      result = :erlang.self()
      assert is_pid(result)
    end
  end

  describe "send/2" do
    test "sends message to PID and returns the message" do
      pid = :erlang.self()
      assert :erlang.send(pid, :hello) == :hello
    end

    test "sends message to atom and returns the message" do
      assert :erlang.send(:some_process, {:msg, 123}) == {:msg, 123}
    end

    test "raises ArgumentError if destination is not a PID or atom" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a pid or atom"), fn ->
        :erlang.send(123, :message)
      end
    end
  end

  describe "setelement/3" do
    test "sets element at position 1" do
      assert :erlang.setelement(1, {:a, :b, :c}, :x) == {:x, :b, :c}
    end

    test "sets element at position 2" do
      assert :erlang.setelement(2, {:a, :b, :c}, :y) == {:a, :y, :c}
    end

    test "sets element at position 3" do
      assert :erlang.setelement(3, {:a, :b, :c}, :z) == {:a, :b, :z}
    end

    test "raises ArgumentError if index is not an integer" do
      assert_error ArgumentError, build_argument_error_msg(1, "not an integer"), fn ->
        :erlang.setelement(:not_int, {:a, :b}, :x)
      end
    end

    test "raises ArgumentError if tuple is not a tuple" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a tuple"), fn ->
        :erlang.setelement(1, [:a, :b], :x)
      end
    end

    test "raises ArgumentError if index is less than 1" do
      assert_error ArgumentError, build_argument_error_msg(1, "out of range"), fn ->
        :erlang.setelement(0, {:a, :b}, :x)
      end
    end

    test "raises ArgumentError if index is greater than tuple size" do
      assert_error ArgumentError, build_argument_error_msg(1, "out of range"), fn ->
        :erlang.setelement(4, {:a, :b, :c}, :x)
      end
    end
  end

  describe "spawn/1" do
    test "returns a PID when given a zero-arity function" do
      result = :erlang.spawn(fn -> :ok end)
      assert is_pid(result)
    end

    test "raises ArgumentError if argument is not a function" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a function of arity 0"), fn ->
        :erlang.spawn(:not_a_function)
      end
    end

    test "raises ArgumentError if function arity is not 0" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a function of arity 0"), fn ->
        :erlang.spawn(fn x -> x end)
      end
    end
  end

  describe "spawn/3" do
    test "returns a PID when given module, function, and args" do
      result = :erlang.spawn(Kernel, :+, [1, 2])
      assert is_pid(result)
    end

    test "raises ArgumentError if module is not an atom" do
      assert_error ArgumentError, build_argument_error_msg(1, "not an atom"), fn ->
        :erlang.spawn(123, :foo, [])
      end
    end

    test "raises ArgumentError if function is not an atom" do
      assert_error ArgumentError, build_argument_error_msg(2, "not an atom"), fn ->
        :erlang.spawn(Kernel, 123, [])
      end
    end

    test "raises ArgumentError if args is not a list" do
      assert_error ArgumentError, build_argument_error_msg(3, "not a list"), fn ->
        :erlang.spawn(Kernel, :+, :not_a_list)
      end
    end

    test "raises ArgumentError if args is not a proper list" do
      assert_error ArgumentError, build_argument_error_msg(3, "not a proper list"), fn ->
        :erlang.spawn(Kernel, :+, [1 | 2])
      end
    end
  end

  describe "size/1" do
    test "returns size of tuple" do
      assert :erlang.size({:a, :b, :c}) == 3
    end

    test "returns size of empty tuple" do
      assert :erlang.size({}) == 0
    end

    test "returns size of binary" do
      assert :erlang.size("hello") == 5
    end

    test "returns size of empty binary" do
      assert :erlang.size("") == 0
    end

    test "raises ArgumentError if not a tuple or binary" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a tuple or binary"), fn ->
        :erlang.size([1, 2, 3])
      end
    end
  end

  describe "split_binary/2" do
    test "splits binary at position 0" do
      binary = "0123456789"

      assert :erlang.split_binary(binary, 0) == {"", "0123456789"}
    end

    test "splits binary at middle position" do
      binary = "0123456789"

      assert :erlang.split_binary(binary, 3) == {"012", "3456789"}
    end

    test "splits binary at end position" do
      binary = "0123456789"

      assert :erlang.split_binary(binary, 10) == {"0123456789", ""}
    end

    test "splits empty binary" do
      binary = ""

      assert :erlang.split_binary(binary, 0) == {"", ""}
    end

    test "splits single character binary" do
      binary = "a"

      assert :erlang.split_binary(binary, 1) == {"a", ""}
    end

    test "splits Unicode binary" do
      binary = "全息图全息图"

      assert :erlang.split_binary(binary, 4) ==
               {<<229, 133, 168, 230>>,
                <<129, 175, 229, 155, 190, 229, 133, 168, 230, 129, 175, 229, 155, 190>>}
    end

    test "raises ArgumentError if the first argument is not a binary" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :split_binary, [:abc, 1]}
    end

    test "raises ArgumentError if the first argument is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :split_binary, [<<1::1, 0::1, 1::1>>, 1]}
    end

    test "raises ArgumentError if the second argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   {:erlang, :split_binary, ["abc", :invalid]}
    end

    test "raises ArgumentError if the second argument is a negative integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   {:erlang, :split_binary, ["abc", -1]}
    end

    test "raises ArgumentError if position is greater than binary size" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   {:erlang, :split_binary, ["abc", 4]}
    end
  end

  describe "tl/1" do
    test "proper list, 1 item" do
      assert :erlang.tl([1]) == []
    end

    test "proper list, 2 items" do
      assert :erlang.tl([1, 2]) == [2]
    end

    test "proper list, 3 items" do
      assert :erlang.tl([1, 2, 3]) == [2, 3]
    end

    test "improper list, 2 items" do
      assert :erlang.tl([1 | 2]) == 2
    end

    test "improper list, 3 items" do
      assert :erlang.tl([1, 2 | 3]) == [2 | 3]
    end
  end

  describe "trunc/1" do
    test "truncates positive float" do
      assert :erlang.trunc(3.9) == 3
    end

    test "truncates negative float" do
      assert :erlang.trunc(-3.9) == -3
    end

    test "truncates float towards zero" do
      assert :erlang.trunc(-0.9) == 0
    end

    test "returns integer unchanged" do
      assert :erlang.trunc(42) == 42
    end

    test "raises ArgumentError if not a number" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a number"), fn ->
        :erlang.trunc(:not_a_number)
      end
    end
  end

  describe "tuple_to_list/1" do
    test "returns a list corresponding to the given tuple" do
      assert :erlang.tuple_to_list({1, 2, 3}) == [1, 2, 3]
    end

    test "raises ArgumentError if the argument is not a tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a tuple"),
                   {:erlang, :tuple_to_list, [:abc]}
    end
  end

  describe "tuple_size/1" do
    test "returns size of tuple" do
      assert :erlang.tuple_size({:a, :b, :c}) == 3
    end

    test "returns size of empty tuple" do
      assert :erlang.tuple_size({}) == 0
    end

    test "raises ArgumentError if not a tuple" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a tuple"), fn ->
        :erlang.tuple_size([1, 2, 3])
      end
    end
  end

  # ========================================
  # Batch 1L: 20 functions
  # ========================================

  describe "append_element/2" do
    test "appends element to empty tuple" do
      assert :erlang.append_element({}, :a) == {:a}
    end

    test "appends element to non-empty tuple" do
      assert :erlang.append_element({1, 2}, 3) == {1, 2, 3}
    end

    test "raises ArgumentError if not a tuple" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a tuple"), fn ->
        :erlang.append_element([1, 2], 3)
      end
    end
  end

  describe "binary_part/3" do
    test "extracts part of binary" do
      assert :erlang.binary_part(<<"hello">>, 1, 3) == <<"ell">>
    end

    test "extracts from start" do
      assert :erlang.binary_part(<<"hello">>, 0, 2) == <<"he">>
    end

    test "raises ArgumentError if not a binary" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a binary"), fn ->
        :erlang.binary_part([1, 2, 3], 0, 1)
      end
    end

    test "raises ArgumentError if position is out of range" do
      assert_error ArgumentError, build_argument_error_msg(2, "out of range"), fn ->
        :erlang.binary_part(<<"hello">>, 10, 1)
      end
    end
  end

  describe "binary_to_list/1" do
    test "converts binary to list of bytes" do
      assert :erlang.binary_to_list(<<1, 2, 3>>) == [1, 2, 3]
    end

    test "converts empty binary" do
      assert :erlang.binary_to_list(<<>>) == []
    end

    test "raises ArgumentError if not a binary" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a binary"), fn ->
        :erlang.binary_to_list([1, 2, 3])
      end
    end
  end

  describe "binary_to_list/3" do
    test "converts binary range to list" do
      assert :erlang.binary_to_list(<<1, 2, 3, 4, 5>>, 2, 4) == [2, 3, 4]
    end

    test "raises ArgumentError if not a binary" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a binary"), fn ->
        :erlang.binary_to_list([1, 2, 3], 1, 2)
      end
    end

    test "raises ArgumentError if range is out of bounds" do
      assert_error ArgumentError, build_argument_error_msg(2, "out of range"), fn ->
        :erlang.binary_to_list(<<1, 2, 3>>, 1, 5)
      end
    end
  end

  describe "ceil/1" do
    test "rounds up float" do
      assert :erlang.ceil(1.2) == 2
    end

    test "rounds up negative float" do
      assert :erlang.ceil(-1.8) == -1
    end

    test "returns integer unchanged" do
      assert :erlang.ceil(42) == 42
    end

    test "raises ArgumentError if not a number" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a number"), fn ->
        :erlang.ceil(:a)
      end
    end
  end

  describe "delete_element/2" do
    test "deletes element from tuple" do
      assert :erlang.delete_element(2, {1, 2, 3}) == {1, 3}
    end

    test "deletes first element" do
      assert :erlang.delete_element(1, {1, 2, 3}) == {2, 3}
    end

    test "raises ArgumentError if not a tuple" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a tuple"), fn ->
        :erlang.delete_element(1, [1, 2, 3])
      end
    end

    test "raises ArgumentError if index out of range" do
      assert_error ArgumentError, build_argument_error_msg(1, "out of range"), fn ->
        :erlang.delete_element(5, {1, 2, 3})
      end
    end
  end

  describe "floor/1" do
    test "rounds down float" do
      assert :erlang.floor(1.8) == 1
    end

    test "rounds down negative float" do
      assert :erlang.floor(-1.2) == -2
    end

    test "returns integer unchanged" do
      assert :erlang.floor(42) == 42
    end

    test "raises ArgumentError if not a number" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a number"), fn ->
        :erlang.floor(:a)
      end
    end
  end

  describe "get/0" do
    test "returns empty list when no keys stored" do
      # Clear process dictionary first
      :erlang.erase()
      assert :erlang.get() == []
    end

    test "returns all key-value pairs" do
      :erlang.erase()
      :erlang.put(:key1, :value1)
      :erlang.put(:key2, :value2)
      result = :erlang.get()
      assert length(result) == 2
      assert {:key1, :value1} in result
      assert {:key2, :value2} in result
    end
  end

  describe "insert_element/3" do
    test "inserts element into tuple" do
      assert :erlang.insert_element(2, {1, 3}, 2) == {1, 2, 3}
    end

    test "inserts at beginning" do
      assert :erlang.insert_element(1, {2, 3}, 1) == {1, 2, 3}
    end

    test "raises ArgumentError if not a tuple" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a tuple"), fn ->
        :erlang.insert_element(1, [1, 2], 0)
      end
    end

    test "raises ArgumentError if index out of range" do
      assert_error ArgumentError, build_argument_error_msg(1, "out of range"), fn ->
        :erlang.insert_element(10, {1, 2}, 3)
      end
    end
  end

  describe "iolist_size/1" do
    test "returns size of flat list" do
      assert :erlang.iolist_size([1, 2, 3]) == 3
    end

    test "returns size of nested iolist" do
      assert :erlang.iolist_size([1, [2, 3], 4]) == 4
    end

    test "returns size of binary" do
      assert :erlang.iolist_size(<<"hello">>) == 5
    end

    test "raises ArgumentError if not an iolist" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a valid iodata"), fn ->
        :erlang.iolist_size(:not_iolist)
      end
    end
  end

  describe "list_to_existing_atom/1" do
    test "converts character list to existing atom" do
      # Create the atom first
      _ = :test_atom
      assert :erlang.list_to_existing_atom([116, 101, 115, 116, 95, 97, 116, 111, 109]) == :test_atom
    end

    test "raises ArgumentError if not a list" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a list"), fn ->
        :erlang.list_to_existing_atom(:not_list)
      end
    end
  end

  describe "make_ref/0" do
    test "returns a reference" do
      ref = :erlang.make_ref()
      assert is_reference(ref)
    end

    test "returns unique references" do
      ref1 = :erlang.make_ref()
      ref2 = :erlang.make_ref()
      assert ref1 != ref2
    end
  end

  describe "make_tuple/2" do
    test "creates tuple with specified size and initial value" do
      assert :erlang.make_tuple(3, :a) == {:a, :a, :a}
    end

    test "creates empty tuple" do
      assert :erlang.make_tuple(0, :a) == {}
    end

    test "raises ArgumentError if size is not integer" do
      assert_error ArgumentError, build_argument_error_msg(1, "not an integer"), fn ->
        :erlang.make_tuple(:not_int, :a)
      end
    end

    test "raises ArgumentError if size is negative" do
      assert_error ArgumentError, build_argument_error_msg(1, "negative size"), fn ->
        :erlang.make_tuple(-1, :a)
      end
    end
  end

  # NOTE: md5/1 is not yet fully implemented in Hologram JavaScript runtime
  # describe "md5/1" do
  #   test "computes MD5 hash of binary" do
  #     hash = :erlang.md5(<<"hello">>)
  #     assert byte_size(hash) == 16
  #   end
  #
  #   test "computes MD5 hash of iolist" do
  #     hash = :erlang.md5([<<"hel">>, <<"lo">>])
  #     assert byte_size(hash) == 16
  #   end
  # end

  describe "monotonic_time/0" do
    test "returns an integer" do
      time = :erlang.monotonic_time()
      assert is_integer(time)
    end

    test "is monotonic increasing" do
      time1 = :erlang.monotonic_time()
      :timer.sleep(1)
      time2 = :erlang.monotonic_time()
      assert time2 >= time1
    end
  end

  describe "put/2" do
    test "stores value and returns undefined for new key" do
      :erlang.erase()
      assert :erlang.put(:new_key, :value) == :undefined
    end

    test "stores value and returns previous value" do
      :erlang.erase()
      :erlang.put(:key, :old_value)
      assert :erlang.put(:key, :new_value) == :old_value
      assert :erlang.get(:key) == :new_value
    end
  end

  describe "system_time/0" do
    test "returns an integer" do
      time = :erlang.system_time()
      assert is_integer(time)
    end

    test "returns positive value" do
      time = :erlang.system_time()
      assert time > 0
    end
  end

  describe "timestamp/0" do
    test "returns a three-element tuple" do
      {mega, secs, micro} = :erlang.timestamp()
      assert is_integer(mega)
      assert is_integer(secs)
      assert is_integer(micro)
    end

    test "microseconds are in valid range" do
      {_mega, _secs, micro} = :erlang.timestamp()
      assert micro >= 0 and micro < 1_000_000
    end
  end

  describe "unique_integer/0" do
    test "returns an integer" do
      result = :erlang.unique_integer()
      assert is_integer(result)
    end

    test "returns unique values" do
      val1 = :erlang.unique_integer()
      val2 = :erlang.unique_integer()
      assert val1 != val2
    end
  end

  describe "unique_integer/1" do
    test "returns positive integer with positive modifier" do
      result = :erlang.unique_integer([:positive])
      assert is_integer(result)
      assert result >= 0
    end

    test "accepts monotonic modifier" do
      result = :erlang.unique_integer([:monotonic])
      assert is_integer(result)
    end

    test "accepts both modifiers" do
      result = :erlang.unique_integer([:positive, :monotonic])
      assert is_integer(result)
      assert result >= 0
    end

    test "raises ArgumentError if not a list" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a list"), fn ->
        :erlang.unique_integer(:not_list)
      end
    end
  end
end
