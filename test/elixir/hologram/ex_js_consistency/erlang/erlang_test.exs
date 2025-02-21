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
end
