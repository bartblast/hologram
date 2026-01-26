defmodule Hologram.ExJsConsistency.Erlang.ErlangTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erlang_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  alias Hologram.Commons.SystemUtils
  alias Hologram.Test.Fixtures.ExJsConsistency.Erlang.Module1

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

  describe "apply/2" do
    setup do
      [
        fun_no_args: fn -> 42 end,
        fun_single_arg: fn x -> x + 10 end,
        fun_multiple_args: fn a, b -> a + b end
      ]
    end

    test "calls anonymous function with no arguments", %{fun_no_args: fun} do
      assert :erlang.apply(fun, []) == 42
    end

    test "calls anonymous function with a single argument", %{fun_single_arg: fun} do
      assert :erlang.apply(fun, [5]) == 15
    end

    test "calls anonymous function with multiple arguments", %{fun_multiple_args: fun} do
      assert :erlang.apply(fun, [1, 2]) == 3
    end

    test "raises BadFunctionError if the first argument is not a function" do
      fun = prevent_term_typing_violation(:not_a_function)

      assert_error BadFunctionError,
                   build_bad_function_error_msg(:not_a_function),
                   fn -> :erlang.apply(fun, []) end
    end

    test "raises ArgumentError if the second argument is not a list", %{fun_no_args: fun} do
      args = prevent_term_typing_violation(:not_a_list)

      assert_error ArgumentError,
                   "argument error",
                   fn -> :erlang.apply(fun, args) end
    end

    test "raises ArgumentError if the second argument is not a proper list", %{
      fun_multiple_args: fun
    } do
      args = prevent_term_typing_violation([1 | 2])

      assert_error ArgumentError,
                   "argument error",
                   fn -> :erlang.apply(fun, args) end
    end

    test "raises BadArityError if arity doesn't match", %{fun_multiple_args: fun} do
      expected_msg =
        ~r'#Function<[0-9]+\.[0-9]+/2 in Hologram\.ExJsConsistency\.Erlang\.ErlangTest\.__ex_unit_setup_[0-9_]+/1> with arity 2 called with 1 argument \(1\)'

      assert_error BadArityError, expected_msg, fn -> :erlang.apply(fun, [1]) end
    end
  end

  describe "apply/3" do
    test "invokes a function with no params" do
      assert :erlang.apply(Module1, :fun_0, []) == 123
    end

    test "invokes a function with a single param" do
      assert :erlang.apply(Module1, :fun_1, [9]) == 109
    end

    test "invokes a function with multiple params" do
      assert :erlang.apply(Module1, :fun_2, [3, 4]) == 7
    end

    test "raises ArgumentError if the first argument is not an atom" do
      expected_msg =
        "you attempted to apply a function named :fun_0 on 123. If you are using Kernel.apply/3, make sure the module is an atom. If you are using the dot syntax, such as module.function(), make sure the left-hand side of the dot is an atom representing a module"

      assert_error ArgumentError, expected_msg, fn ->
        :erlang.apply(123, :fun_0, [])
      end
    end

    test "raises ArgumentError if the second argument is not an atom" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an atom"),
                   {:erlang, :apply, [Module1, 123, []]}
    end

    test "raises ArgumentError if the third argument is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a list"),
                   {:erlang, :apply, [Module1, :fun_0, 123]}
    end

    test "raises ArgumentError if the third argument is not a proper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not a proper list"),
                   {:erlang, :apply, [Module1, :fun_2, [1 | 2]]}
    end

    test "raises UndefinedFunctionError if the module doesn't exist" do
      expected_msg =
        build_undefined_function_error_msg({NonexistentModule, :fun_2, 2}, [], false)

      assert_error UndefinedFunctionError, expected_msg, fn ->
        :erlang.apply(NonexistentModule, :fun_2, [1, 2])
      end
    end

    test "raises UndefinedFunctionError if the function doesn't exist" do
      expected_msg = build_undefined_function_error_msg({Module1, :nonexistent_fun, 2})

      assert_error UndefinedFunctionError, expected_msg, fn ->
        :erlang.apply(Module1, :nonexistent_fun, [1, 2])
      end
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

  describe "band/2" do
    test "valid arguments" do
      # 5 = 0b00000101, 3 = 0b00000011, 1 = 0b00000001
      assert :erlang.band(5, 3) == 1
    end

    test "both arguments are zero" do
      # 0 = 0b00000000
      assert :erlang.band(0, 0) == 0
    end

    test "left argument is zero" do
      # 0 = 0b00000000, 5 = 0b00000101
      assert :erlang.band(0, 5) == 0
    end

    test "right argument is zero" do
      # 5 = 0b00000101, 0 = 0b00000000
      assert :erlang.band(5, 0) == 0
    end

    test "left argument is negative" do
      # -5 = 0b11111011, 15 = 0b00001111, 11 = 0b00001011
      assert :erlang.band(-5, 15) == 11
    end

    test "right argument is negative" do
      # 15 = 0b00001111, -5 = 0b11111011, 11 = 0b00001011
      assert :erlang.band(15, -5) == 11
    end

    test "arguments above JS Number.MAX_SAFE_INTEGER" do
      # Number.MAX_SAFE_INTEGER == 9_007_199_254_740_991
      # 805_215_019_090_496_300 = 0b101100101100101100101100101100101100101100101100101100101100
      # 457_508_533_574_145_625 = 0b011001011001011001011001011001011001011001011001011001011001
      # 146_402_730_743_726_600 = 0b001000001000001000001000001000001000001000001000001000001000
      assert :erlang.band(805_215_019_090_496_300, 457_508_533_574_145_625) ==
               146_402_730_743_726_600
    end

    test "arguments below JS Number.MIN_SAFE_INTEGER" do
      # Number.MIN_SAFE_INTEGER == -9_007_199_254_740_991
      #   -347_706_485_516_350_676 = 0b1111101100101100101100101100101100101100101100101100101100101100
      #   -695_412_971_032_701_351 = 0b1111011001011001011001011001011001011001011001011001011001011001
      # -1_006_518_773_863_120_376 = 0b1111001000001000001000001000001000001000001000001000001000001000
      assert :erlang.band(-347_706_485_516_350_676, -695_412_971_032_701_351) ==
               -1_006_518_773_863_120_376
    end

    test "raises ArithmeticError if the first argument is not an integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: Bitwise.band(5.0, 3)",
                   {:erlang, :band, [5.0, 3]}
    end

    test "raises ArithmeticError if the second argument is not an integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: Bitwise.band(5, 3.0)",
                   {:erlang, :band, [5, 3.0]}
    end
  end

  describe "binary_part/3" do
    test "subject is a text binary" do
      assert :erlang.binary_part("mygoldfish", 6, 4) == "fish"
    end

    test "subject is a byte binary" do
      assert :erlang.binary_part(<<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>, 4, 2) == <<5, 6>>
    end

    test "subject is empty" do
      assert :erlang.binary_part("", 0, 0) == ""
    end

    test "subject contains multi-byte unicode characters" do
      # The character "á" is represented in UTF-8 as two bytes: <<195, 161>>
      assert :erlang.binary_part("á", 0, 1) == <<195>>
    end

    test "start is zero" do
      assert :erlang.binary_part("goldfish", 0, 4) == "gold"
    end

    test "start is at the end of the binary" do
      assert :erlang.binary_part("goldfish", 8, -4) == "fish"
    end

    test "length is negative" do
      assert :erlang.binary_part("golden retriever", 16, -9) == "retriever"
    end

    test "length is zero" do
      assert :erlang.binary_part("goldfish", 2, 0) == ""
    end

    test "from the middle of the binary" do
      assert :erlang.binary_part("golden retriever", 7, 9) == "retriever"
    end

    test "takes whole binary" do
      assert :erlang.binary_part("goldfish", 0, 8) == "goldfish"
    end

    test "takes whole binary reversed" do
      assert :erlang.binary_part("goldfish", 8, -8) == "goldfish"
    end

    test "raises ArgumentError if the first argument is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_part, [:abc, 1, 2]}
    end

    test "raises ArgumentError if the first argument is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_part, [<<1::1, 0::1, 1::1>>, 1, 2]}
    end

    test "raises ArgumentError if the second argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer"),
                   {:erlang, :binary_part, ["goldfish", 1.0, 2]}
    end

    test "raises ArgumentError if the second argument is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   {:erlang, :binary_part, ["goldfish", -1, 2]}
    end

    test "raises ArgumentError if the second argument is larger than the size of the first argument" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "out of range"),
                   {:erlang, :binary_part, ["goldfish", 9, 2]}
    end

    test "raises ArgumentError if the second argument is zero and third argument is larger than the size of the first argument" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "out of range"),
                   {:erlang, :binary_part, ["goldfish", 0, 9]}
    end

    test "raises ArgumentError if the third argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "not an integer"),
                   {:erlang, :binary_part, ["goldfish", 1, 2.0]}
    end

    test "raises ArgumentError if the third argument is positive and the second and third arguments summed is larger than the size of the first argument" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "out of range"),
                   {:erlang, :binary_part, ["goldfish", 1, 8]}
    end

    test "raises ArgumentError if the third argument is negative and the second and third arguments summed is smaller than zero" do
      assert_error ArgumentError,
                   build_argument_error_msg(3, "out of range"),
                   {:erlang, :binary_part, ["goldfish", 4, -5]}
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

  describe "binary_to_float/1" do
    test "positive float without sign in decimal notation" do
      assert :erlang.binary_to_float("1.23") == 1.23
    end

    test "positive float with sign in decimal notation" do
      assert :erlang.binary_to_float("+1.23") == 1.23
    end

    test "negative float in decimal notation" do
      assert :erlang.binary_to_float("-1.23") == -1.23
    end

    test "unsigned zero float in decimal notation" do
      assert :erlang.binary_to_float("0.0") === 0.0
    end

    test "signed positive zero float in decimal notation" do
      assert :erlang.binary_to_float("+0.0") === +0.0
    end

    test "signed negative zero float in decimal notation" do
      assert :erlang.binary_to_float("-0.0") === -0.0
    end

    test "positive float in scientific notation" do
      assert :erlang.binary_to_float("1.23456e+3") == 1234.56
    end

    test "negative float in scientific notation" do
      assert :erlang.binary_to_float("-1.23456e+3") == -1234.56
    end

    test "unsigned zero float in scientific notation" do
      assert :erlang.binary_to_float("0.0e+1") === 0.0
    end

    test "signed positive zero float in scientific notation" do
      assert :erlang.binary_to_float("+0.0e+1") === +0.0
    end

    test "signed negative zero float in scientific notation" do
      assert :erlang.binary_to_float("-0.0e+1") === -0.0
    end

    test "positive integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["123"]}
    end

    test "negative integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["-123"]}
    end

    test "zero integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["0"]}
    end

    test "with leading zeros" do
      assert :erlang.binary_to_float("00012.34") == 12.34
    end

    test "uppercase scientific notation" do
      assert :erlang.binary_to_float("1.23456E3") == 1234.56
    end

    test "negative exponent" do
      assert :erlang.binary_to_float("1.23e-3") == 0.00123
    end

    test "non-binary bitstring input" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_to_float, [<<1::1, 0::1, 1::1>>]}
    end

    test "non-bitstring input" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_to_float, [:abc]}
    end

    test "with underscore" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["1_000.5"]}
    end

    test "invalid float format" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["12.3.4"]}
    end

    test "non-numeric text" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["abc"]}
    end

    test "empty input" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, [""]}
    end

    test "decimal point only" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["."]}
    end

    test "with leading dot" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, [".5"]}
    end

    test "with trailing dot" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["5."]}
    end

    test "scientific notation without the fractional part" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["3e10"]}
    end

    test "with trailing exponent marker" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["2e"]}
    end

    test "with leading whitespace" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, [" 12.3"]}
    end

    test "with trailing whitespace" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["12.3 "]}
    end

    test "with multiple exponent markers" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["1e2e3"]}
    end

    test "Infinity text" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["Infinity"]}
    end

    test "hex-style JS float" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a float"),
                   {:erlang, :binary_to_float, ["0x1.fp2"]}
    end
  end

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

  describe "binary_to_list/1" do
    test "converts a bytes-based binary to a list of integers" do
      assert :erlang.binary_to_list(<<1, 2, 3>>) == [1, 2, 3]
    end

    test "converts a text-based binary to a list of integers" do
      assert :erlang.binary_to_list("abc") == [97, 98, 99]
    end

    test "converts an empty bytes-based binary to an empty list" do
      assert :erlang.binary_to_list(<<>>) == []
    end

    test "converts an empty text-based binary to an empty list" do
      assert :erlang.binary_to_list("") == []
    end

    test "raises ArgumentError if the argument is not a bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_to_list, [123]}
    end

    test "raises ArgumentError if the argument is a non-binary bitstring" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a binary"),
                   {:erlang, :binary_to_list, [<<5::size(3)>>]}
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

  describe "bor/2" do
    test "both arguments are positive" do
      # 4 = 0b00000100, 3 = 0b00000011, 7 = 0b00000111
      assert :erlang.bor(4, 3) == 7
    end

    test "both arguments are zero" do
      # 0 = 0b00000000
      assert :erlang.bor(0, 0) == 0
    end

    test "left argument is zero" do
      # 0 = 0b00000000, 8 = 0b00001000
      assert :erlang.bor(0, 8) == 8
    end

    test "right argument is zero" do
      # 4 = 0b00000100, 0 = 0b00000000
      assert :erlang.bor(4, 0) == 4
    end

    test "left argument is negative" do
      # -4 = 0b11111100, 3 = 0b00000011, -1 = 0b11111111
      assert :erlang.bor(-4, 3) == -1
    end

    test "right argument is negative" do
      # 4 = 0b00000100, -3 = 0b11111101
      assert :erlang.bor(4, -3) == -3
    end

    test "both arguments are negative" do
      # -4 = 0b11111100, -3 = 0b11111101
      assert :erlang.bor(-4, -3) == -3
    end

    test "arguments above JS Number.MAX_SAFE_INTEGER" do
      # Number.MAX_SAFE_INTEGER == 9_007_199_254_740_991
      #   805_215_019_090_496_300 = 0b101100101100101100101100101100101100101100101100101100101100
      #   457_508_533_574_145_625 = 0b011001011001011001011001011001011001011001011001011001011001
      # 1_116_320_821_920_915_325 = 0b111101111101111101111101111101111101111101111101111101111101
      assert :erlang.bor(805_215_019_090_496_300, 457_508_533_574_145_625) ==
               1_116_320_821_920_915_325
    end

    test "arguments below JS Number.MIN_SAFE_INTEGER" do
      # Number.MIN_SAFE_INTEGER == -9_007_199_254_740_991
      # -347_706_485_516_350_676 = 0b1111101100101100101100101100101100101100101100101100101100101100
      # -695_412_971_032_701_351 = 0b1111011001011001011001011001011001011001011001011001011001011001
      #  -36_600_682_685_931_651 = 0b1111111101111101111101111101111101111101111101111101111101111101
      assert :erlang.bor(-347_706_485_516_350_676, -695_412_971_032_701_351) ==
               -36_600_682_685_931_651
    end

    test "raises ArithmeticError if the first argument is not an integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: Bitwise.bor(1.0, 2)",
                   {:erlang, :bor, [1.0, 2]}
    end

    test "raises ArithmeticError if the second argument is not an integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: Bitwise.bor(1, 2.0)",
                   {:erlang, :bor, [1, 2.0]}
    end
  end

  describe "bsr/2" do
    test "common usage" do
      # 16 = 0b00010000, 8 = 0b00001000
      assert :erlang.bsr(16, 1) == 8
    end

    test "zero shift" do
      # 247 = 0b11110111
      assert :erlang.bsr(247, 0) == 247
    end

    test "shift left via negative shift" do
      # 1 = 0b00000001, 16 = 0b00010000
      assert :erlang.bsr(1, -4) == 16
    end

    test "negative keeps sign bit" do
      # -16 = 0b11110000, -8 = 0b11111000
      assert :erlang.bsr(-16, 1) == -8
    end

    test "shift beyond size for positive integer" do
      # 255 = 0b1111111, 0 = 0b00000000
      assert :erlang.bsr(255, 9) == 0
    end

    test "shift beyond size for negative integer" do
      # -127 = 0b10000001, -1 = 0b11111111
      assert :erlang.bsr(-127, 8) == -1
    end

    test "above JS Number.MAX_SAFE_INTEGER" do
      # Number.MAX_SAFE_INTEGER == 9_007_199_254_740_991
      # 18_014_398_509_481_984 = 0b1000000000000000000000000000000000000000000000000000000
      #  9_007_199_254_740_992 = 0b0100000000000000000000000000000000000000000000000000000
      assert :erlang.bsr(18_014_398_509_481_984, 1) == 9_007_199_254_740_992
    end

    test "below JS Number.MIN_SAFE_INTEGER" do
      # Number.MIN_SAFE_INTEGER == -9_007_199_254_740_991
      # -18_014_398_509_481_984 = 0b1111111111000000000000000000000000000000000000000000000000000000
      #  -9_007_199_254_740_992 = 0b1111111111100000000000000000000000000000000000000000000000000000
      assert :erlang.bsr(-18_014_398_509_481_984, 1) == -9_007_199_254_740_992
    end

    test "raises ArithmeticError if the first argument is not an integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: Bitwise.bsr(1.0, 2)",
                   {:erlang, :bsr, [1.0, 2]}
    end

    test "raises ArithmeticError if the second argument is not an integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: Bitwise.bsr(1, 2.0)",
                   {:erlang, :bsr, [1, 2.0]}
    end
  end

  describe "bxor/2" do
    test "valid arguments" do
      # 5 = 0b00000101, 3 = 0b00000011, 6 = 0b00000110
      assert :erlang.bxor(5, 3) == 6
    end

    test "both arguments are zero" do
      # 0 = 0b00000000
      assert :erlang.bxor(0, 0) == 0
    end

    test "left argument is zero" do
      # 0 = 0b00000000, 5 = 0b00000101
      assert :erlang.bxor(0, 5) == 5
    end

    test "right argument is zero" do
      # 5 = 0b00000101, 0 = 0b00000000
      assert :erlang.bxor(5, 0) == 5
    end

    test "same values result in zero" do
      # 5 = 0b00000101, 0 = 0b00000000
      assert :erlang.bxor(5, 5) == 0
    end

    test "left argument is negative" do
      # -5 = 0b11111011, 5 = 0b00000101, -2 = 0b11111110
      assert :erlang.bxor(-5, 5) == -2
    end

    test "right argument is negative" do
      # 5 = 0b00000101, -5 = 0b11111011, -2 = 0b11111110
      assert :erlang.bxor(5, -5) == -2
    end

    test "both arguments are negative" do
      # -5 = 0b11111011, -3 = 0b11111101, 6 = 0b00000110
      assert :erlang.bxor(-5, -3) == 6
    end

    test "arguments above JS Number.MAX_SAFE_INTEGER" do
      # Number.MAX_SAFE_INTEGER == 9_007_199_254_740_991
      # 805_215_019_090_496_300 = 0b101100101100101100101100101100101100101100101100101100101100
      # 457_508_533_574_145_625 = 0b011001011001011001011001011001011001011001011001011001011001
      # 969_918_091_177_188_725 = 0b110101110101110101110101110101110101110101110101110101110101
      assert :erlang.bxor(805_215_019_090_496_300, 457_508_533_574_145_625) ==
               969_918_091_177_188_725
    end

    test "arguments below JS Number.MIN_SAFE_INTEGER" do
      # Number.MIN_SAFE_INTEGER == -9_007_199_254_740_991
      # -347_706_485_516_350_676 = 0b1111101100101100101100101100101100101100101100101100101100101100
      # -695_412_971_032_701_351 = 0b1111011001011001011001011001011001011001011001011001011001011001
      #  969_918_091_177_188_725 = 0b0000110101110101110101110101110101110101110101110101110101110101
      assert :erlang.bxor(-347_706_485_516_350_676, -695_412_971_032_701_351) ==
               969_918_091_177_188_725
    end

    test "raises ArithmeticError if the first argument is not an integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: Bitwise.bxor(5.0, 3)",
                   {:erlang, :bxor, [5.0, 3]}
    end

    test "raises ArithmeticError if the second argument is not an integer" do
      assert_error ArithmeticError,
                   "bad argument in arithmetic expression: Bitwise.bxor(5, 3.0)",
                   {:erlang, :bxor, [5, 3.0]}
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

  describe "ceil/1" do
    test "rounds positive float with fractional part up" do
      assert :erlang.ceil(1.23) == 2
    end

    test "rounds negative float with fractional part up toward zero" do
      assert :erlang.ceil(-1.23) == -1
    end

    test "keeps positive float without fractional part unchanged" do
      assert :erlang.ceil(1.0) == 1
    end

    test "keeps negative float without fractional part unchanged" do
      assert :erlang.ceil(-1.0) == -1
    end

    test "keeps signed negative zero float unchanged" do
      assert :erlang.ceil(-0.0) == 0
    end

    test "keeps signed positive zero float unchanged" do
      assert :erlang.ceil(+0.0) == 0
    end

    test "keeps unsigned zero float unchanged" do
      assert :erlang.ceil(0.0) == 0
    end

    test "keeps positive integer unchanged" do
      assert :erlang.ceil(1) == 1
    end

    test "keeps negative integer unchanged" do
      assert :erlang.ceil(-1) == -1
    end

    test "keeps zero integer unchanged" do
      assert :erlang.ceil(0) == 0
    end

    test "raises ArgumentError if the argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:erlang, :ceil, [:abc]}
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
      assert :erlang.float(1) == 1.0
    end

    test "is idempotent for float" do
      assert :erlang.float(1.0) == 1.0
    end

    test "raises ArgumentError if the argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:erlang, :float, [:abc]}
    end
  end

  describe "float_to_binary/2" do
    @input_above_10 1000 / 3
    @input_between_1_and_10 10 / 3
    @input_below_1 1 / 30

    # default format is equaivalent to [{:scientific, 20}]

    test "default format, input > 10, padding not needed" do
      assert :erlang.float_to_binary(@input_above_10, []) == "3.33333333333333314386e+02"
    end

    test "default format, input > 10, padding needed" do
      assert :erlang.float_to_binary(128.0, []) == "1.28000000000000000000e+02"
    end

    test "default format, input between 1 and 10, padding not needed" do
      assert :erlang.float_to_binary(@input_between_1_and_10, []) == "3.33333333333333348136e+00"
    end

    test "default format, input between 1 and 10, padding needed" do
      assert :erlang.float_to_binary(2.0, []) == "2.00000000000000000000e+00"
    end

    test "default format, input < 1, padding not needed" do
      assert :erlang.float_to_binary(@input_below_1, []) == "3.33333333333333328707e-02"
    end

    test "default format, input < 1, padding needed" do
      assert :erlang.float_to_binary(0.0625, []) == "6.25000000000000000000e-02"
    end

    test "default format, input is signed positive zero" do
      assert :erlang.float_to_binary(+0.0, []) == "0.00000000000000000000e+00"
    end

    test "default format, input is signed negative zero" do
      assert :erlang.float_to_binary(-0.0, []) == "-0.00000000000000000000e+00"
    end

    test "default format, input is unsigned zero" do
      assert :erlang.float_to_binary(0.0, []) == "0.00000000000000000000e+00"
    end

    test "default format, input is negative" do
      assert :erlang.float_to_binary(-@input_between_1_and_10, []) ==
               "-3.33333333333333348136e+00"
    end

    test ":decimals option, input > 10, padding not needed" do
      assert :erlang.float_to_binary(@input_above_10, [{:decimals, 4}]) == "333.3333"
    end

    test ":decimals option, input > 10, padding needed" do
      assert :erlang.float_to_binary(128.0, [{:decimals, 4}]) == "128.0000"
    end

    test ":decimals option, input between 1 and 10, padding not needed" do
      assert :erlang.float_to_binary(@input_between_1_and_10, [{:decimals, 4}]) == "3.3333"
    end

    test ":decimals option, input between 1 and 10, padding needed" do
      assert :erlang.float_to_binary(2.0, [{:decimals, 4}]) == "2.0000"
    end

    test ":decimals option, input < 1, padding not needed" do
      assert :erlang.float_to_binary(@input_below_1, [{:decimals, 4}]) == "0.0333"
    end

    test ":decimals option, input < 1, padding needed" do
      assert :erlang.float_to_binary(0.5, [{:decimals, 4}]) == "0.5000"
    end

    test ":decimals option, input is signed positive zero" do
      assert :erlang.float_to_binary(+0.0, [{:decimals, 4}]) == "0.0000"
    end

    test ":decimals option, input is signed negative zero" do
      assert :erlang.float_to_binary(-0.0, [{:decimals, 4}]) == "-0.0000"
    end

    test ":decimals option, input is unsigned zero" do
      assert :erlang.float_to_binary(0.0, [{:decimals, 4}]) == "0.0000"
    end

    test ":decimals option, input is negative" do
      assert :erlang.float_to_binary(-@input_between_1_and_10, [{:decimals, 4}]) == "-3.3333"
    end

    test ":decimals option, accepts option value 0 (the min allowed value)" do
      assert :erlang.float_to_binary(123.45, [{:decimals, 0}]) == "123"
    end

    test ":decimals option, accepts option value 253 (the max allowed value)" do
      result = :erlang.float_to_binary(@input_below_1, [{:decimals, 253}])

      expected =
        "0.033333333333333332870740406406184774823486804962158203125" <>
          String.duplicate("0", 196)

      assert result == expected
    end

    test ":decimals option, raises ArgumentError if option is not an integer" do
      expected_msg = build_argument_error_msg(2, "invalid option in list")

      assert_error ArgumentError, expected_msg, fn ->
        :erlang.float_to_binary(@input_above_10, [{:decimals, 1.23}])
      end
    end

    test ":decimals option, raises ArgumentError if option is less than zero" do
      expected_msg = build_argument_error_msg(2, "invalid option in list")

      assert_error ArgumentError, expected_msg, fn ->
        :erlang.float_to_binary(@input_above_10, [{:decimals, -1}])
      end
    end

    test ":decimals option, raises ArgumentError if option is greater than 253" do
      expected_msg = build_argument_error_msg(2, "invalid option in list")

      assert_error ArgumentError, expected_msg, fn ->
        :erlang.float_to_binary(@input_above_10, [{:decimals, 254}])
      end
    end

    test ":scientific option, positive option value, input > 10, padding not needed" do
      assert :erlang.float_to_binary(@input_above_10, [{:scientific, 4}]) == "3.3333e+02"
    end

    test ":scientific option, positive option value, input > 10, padding needed" do
      assert :erlang.float_to_binary(128.0, [{:scientific, 4}]) == "1.2800e+02"
    end

    test ":scientific option, positive option value, input between 1 and 10, padding not needed" do
      assert :erlang.float_to_binary(@input_between_1_and_10, [{:scientific, 4}]) == "3.3333e+00"
    end

    test ":scientific option, positive option value, input between 1 and 10, padding needed" do
      assert :erlang.float_to_binary(2.0, [{:scientific, 4}]) == "2.0000e+00"
    end

    test ":scientific option, positive option value, input < 1, padding not needed" do
      assert :erlang.float_to_binary(@input_below_1, [{:scientific, 4}]) == "3.3333e-02"
    end

    test ":scientific option, positive option value, input < 1, padding needed" do
      assert :erlang.float_to_binary(0.0625, [{:scientific, 4}]) == "6.2500e-02"
    end

    test ":scientific option, positive option value, input is signed positive zero" do
      assert :erlang.float_to_binary(+0.0, [{:scientific, 4}]) == "0.0000e+00"
    end

    test ":scientific option, positive option value, input is signed negative zero" do
      assert :erlang.float_to_binary(-0.0, [{:scientific, 4}]) == "-0.0000e+00"
    end

    test ":scientific option, positive option value, input is unsigned zero" do
      assert :erlang.float_to_binary(0.0, [{:scientific, 4}]) == "0.0000e+00"
    end

    test ":scientific option, positive option value, input is negative" do
      assert :erlang.float_to_binary(-@input_between_1_and_10, [{:scientific, 4}]) ==
               "-3.3333e+00"
    end

    test ":scientific option, zero option value, input > 10" do
      assert :erlang.float_to_binary(@input_above_10, [{:scientific, 0}]) == "3e+02"
    end

    test ":scientific option, zero option value, input between 1 and 10" do
      assert :erlang.float_to_binary(@input_between_1_and_10, [{:scientific, 0}]) == "3e+00"
    end

    test ":scientific option, zero option value, input < 1" do
      assert :erlang.float_to_binary(@input_below_1, [{:scientific, 0}]) == "3e-02"
    end

    test ":scientific option, negative option value, input > 10, padding not needed" do
      assert :erlang.float_to_binary(@input_above_10, [{:scientific, -4}]) == "3.333333e+02"
    end

    test ":scientific option, negative option value, input > 10, padding needed" do
      assert :erlang.float_to_binary(128.0, [{:scientific, -4}]) == "1.280000e+02"
    end

    test ":scientific option, negative option value, input between 1 and 10, padding not needed" do
      assert :erlang.float_to_binary(@input_between_1_and_10, [{:scientific, -4}]) ==
               "3.333333e+00"
    end

    test ":scientific option, negative option value, input between 1 and 10, padding needed" do
      assert :erlang.float_to_binary(2.0, [{:scientific, -4}]) == "2.000000e+00"
    end

    test ":scientific option, negative option value, input < 1, padding not needed" do
      assert :erlang.float_to_binary(@input_below_1, [{:scientific, -4}]) == "3.333333e-02"
    end

    test ":scientific option, negative option value, input < 1, padding needed" do
      assert :erlang.float_to_binary(0.0625, [{:scientific, -4}]) == "6.250000e-02"
    end

    test ":scientific option, negative option value, input is signed positive zero" do
      assert :erlang.float_to_binary(+0.0, [{:scientific, -4}]) == "0.000000e+00"
    end

    test ":scientific option, negative option value, input is signed negative zero" do
      assert :erlang.float_to_binary(-0.0, [{:scientific, -4}]) == "-0.000000e+00"
    end

    test ":scientific option, negative option value, input is unsigned zero" do
      assert :erlang.float_to_binary(0.0, [{:scientific, -4}]) == "0.000000e+00"
    end

    test ":scientific option, negative option value, input is negative" do
      assert :erlang.float_to_binary(-@input_between_1_and_10, [{:scientific, -4}]) ==
               "-3.333333e+00"
    end

    test ":scientific option, accepts option value 249 (the max allowed value)" do
      result = :erlang.float_to_binary(@input_between_1_and_10, [{:scientific, 249}])

      expected =
        "3.333333333333333481363069950020872056484222412109375" <>
          String.duplicate("0", 198) <> "e+00"

      assert result == expected
    end

    test ":scientific option, raises ArgumentError if option is not an integer" do
      expected_msg = build_argument_error_msg(2, "invalid option in list")

      assert_error ArgumentError, expected_msg, fn ->
        :erlang.float_to_binary(@input_above_10, [{:scientific, 1.23}])
      end
    end

    test ":scientific option, raises ArgumentError if option is greater than 249" do
      expected_msg = build_argument_error_msg(2, "invalid option in list")

      assert_error ArgumentError, expected_msg, fn ->
        :erlang.float_to_binary(@input_above_10, [{:scientific, 250}])
      end
    end

    test ":short option, input > 10, infinite" do
      assert :erlang.float_to_binary(@input_above_10, [:short]) == "333.3333333333333"
    end

    test ":short option, input > 10, finite" do
      assert :erlang.float_to_binary(128.5, [:short]) == "128.5"
    end

    test ":short option, input between 1 and 10, infinite" do
      assert :erlang.float_to_binary(@input_between_1_and_10, [:short]) == "3.3333333333333335"
    end

    test ":short option, input between 1 and 10, finite" do
      assert :erlang.float_to_binary(8.5, [:short]) == "8.5"
    end

    test ":short option, input < 1, infinite" do
      assert :erlang.float_to_binary(@input_below_1, [:short]) == "0.03333333333333333"
    end

    test ":short option, input < 1, finite" do
      assert :erlang.float_to_binary(0.25, [:short]) == "0.25"
    end

    test ":short option, input is signed positive zero" do
      assert :erlang.float_to_binary(+0.0, [:short]) == "0.0"
    end

    test ":short option, input is signed negative zero" do
      assert :erlang.float_to_binary(-0.0, [:short]) == "-0.0"
    end

    test ":short option, input is unsigned zero" do
      assert :erlang.float_to_binary(0.0, [:short]) == "0.0"
    end

    test ":short option, input is negative" do
      assert :erlang.float_to_binary(-@input_between_1_and_10, [:short]) ==
               "-3.3333333333333335"
    end

    test ":short option, decimal is shorter than exponential" do
      # 0.001: Decimal "0.001" (5 chars) vs Exponential "1.0e-3" (6 chars) → decimal wins
      assert :erlang.float_to_binary(0.001, [:short]) == "0.001"
    end

    test ":short option, exponential is shorter than decimal" do
      # 0.00099: Decimal "0.00099" (7 chars) vs Exponential "9.9e-4" (6 chars) → exponential wins
      assert :erlang.float_to_binary(0.00099, [:short]) == "9.9e-4"
    end

    test ":short option, tie - decimal wins" do
      # 0.0009: Decimal "0.0009" (6 chars) vs Exponential "9.0e-4" (6 chars) → decimal wins tie
      assert :erlang.float_to_binary(0.0009, [:short]) == "0.0009"
    end

    test ":short option, value at 2^53 boundary uses exponential" do
      # 2^53 = 9_007_199_254_740_992
      assert :erlang.float_to_binary(9_007_199_254_740_992.0, [:short]) == "9.007199254740992e15"
    end

    test ":short option, value below 2^53 boundary uses decimal" do
      # 2^53 - 1 = 9_007_199_254_740_991
      assert :erlang.float_to_binary(9_007_199_254_740_991.0, [:short]) ==
               "9007199254740991.0"
    end

    test ":short option, value at -2^53 boundary uses exponential" do
      # -2^53 = -9_007_199_254_740_992
      assert :erlang.float_to_binary(-9_007_199_254_740_992.0, [:short]) ==
               "-9.007199254740992e15"
    end

    test ":short option, value above -2^53 boundary uses decimal" do
      # -2^53 + 1 = -9_007_199_254_740_991
      assert :erlang.float_to_binary(-9_007_199_254_740_991.0, [:short]) ==
               "-9007199254740991.0"
    end

    test ":compact option by itself is same as default format" do
      assert :erlang.float_to_binary(@input_above_10, [:compact]) ==
               :erlang.float_to_binary(@input_above_10, [])
    end

    test ":compact + :decimals option, input > 10, infinite" do
      assert :erlang.float_to_binary(@input_above_10, [:compact, {:decimals, 4}]) == "333.3333"
    end

    test ":compact + :decimals option, input > 10, finite" do
      assert :erlang.float_to_binary(128.5, [:compact, {:decimals, 4}]) == "128.5"
    end

    test ":compact + :decimals option, input between 1 and 10, infinite" do
      assert :erlang.float_to_binary(@input_between_1_and_10, [:compact, {:decimals, 4}]) ==
               "3.3333"
    end

    test ":compact + :decimals option, input between 1 and 10, finite" do
      assert :erlang.float_to_binary(8.5, [:compact, {:decimals, 4}]) == "8.5"
    end

    test ":compact + :decimals option, input < 1, infinite" do
      assert :erlang.float_to_binary(@input_below_1, [:compact, {:decimals, 4}]) == "0.0333"
    end

    test ":compact + :decimals option, input < 1, finite" do
      assert :erlang.float_to_binary(0.25, [:compact, {:decimals, 4}]) == "0.25"
    end

    test ":compact + :decimals option, input is signed positive zero" do
      assert :erlang.float_to_binary(+0.0, [:compact, {:decimals, 4}]) == "0.0"
    end

    test ":compact + :decimals option, input is signed negative zero" do
      assert :erlang.float_to_binary(-0.0, [:compact, {:decimals, 4}]) == "-0.0"
    end

    test ":compact + :decimals option, input is unsigned zero" do
      assert :erlang.float_to_binary(0.0, [:compact, {:decimals, 4}]) == "0.0"
    end

    test ":compact + :decimals option, order of options doesn't matter" do
      assert :erlang.float_to_binary(128.5, [{:decimals, 4}, :compact]) == "128.5"
    end

    test ":compact + :decimals option, accepts compact option with decimals 0" do
      assert :erlang.float_to_binary(128.0, [:compact, {:decimals, 0}]) == "128"
    end

    test ":compact option is ignored when used with :scientific option" do
      scientific_result = :erlang.float_to_binary(@input_above_10, [{:scientific, 4}])

      assert :erlang.float_to_binary(@input_above_10, [{:scientific, 4}, :compact]) ==
               scientific_result

      assert :erlang.float_to_binary(@input_above_10, [:compact, {:scientific, 4}]) ==
               scientific_result
    end

    test ":compact option is ignored when used with :short option" do
      short_result = :erlang.float_to_binary(@input_above_10, [:short])

      assert :erlang.float_to_binary(@input_above_10, [:short, :compact]) == short_result
      assert :erlang.float_to_binary(@input_above_10, [:compact, :short]) == short_result
    end

    test "multiple opts - last opt is :scientific" do
      assert :erlang.float_to_binary(7.12, [{:decimals, 4}, {:scientific, 3}]) == "7.120e+00"
    end

    test "multiple opts - last opt is :scientific followed by :compact" do
      assert :erlang.float_to_binary(7.12, [{:decimals, 4}, {:scientific, 3}, :compact]) ==
               "7.120e+00"
    end

    test "multiple opts - last opt is :decimals" do
      assert :erlang.float_to_binary(7.12, [:short, {:decimals, 4}]) == "7.1200"
    end

    test "multiple opts - last opt is :decimals followed by :compact" do
      assert :erlang.float_to_binary(7.12, [{:scientific, 3}, {:decimals, 4}, :compact]) == "7.12"
    end

    test "multiple opts - last opt is :short" do
      assert :erlang.float_to_binary(7.12, [{:scientific, 3}, :short]) == "7.12"
    end

    test "multiple opts - last opt is :short followed by :compact" do
      assert :erlang.float_to_binary(7.12, [{:scientific, 3}, :short, :compact]) == "7.12"
    end

    test "allows result with exactly 255 bytes (boundary condition)" do
      # Test boundary: 1.0 with decimals=253 → "1." + 253 zeros = 255 chars (allowed)
      result = :erlang.float_to_binary(1.0, [{:decimals, 253}])

      assert String.length(result) == 255
      assert result == "1." <> String.duplicate("0", 253)
    end

    test "raises ArgumentError if result exceeds 255-byte buffer limit" do
      # Native Erlang enforces a 256-byte buffer limit (result must be < 256) but reports it as
      # "2nd argument: invalid option in list" rather than a clearer error message
      # Test boundary: 10.0 with decimals=253 → "10." + 253 zeros = 256 chars (not allowed)
      expected_msg = build_argument_error_msg(2, "invalid option in list")

      assert_error ArgumentError, expected_msg, fn ->
        :erlang.float_to_binary(10.0, [{:decimals, 253}])
      end
    end

    test "raises ArgumentError if the first argument is not a float" do
      assert_error ArgumentError, build_argument_error_msg(1, "not a float"), fn ->
        :erlang.float_to_binary(123, [:short])
      end
    end

    test "raises ArgumentError if the second argument is not a list" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a list"), fn ->
        :erlang.float_to_binary(@input_above_10, 123)
      end
    end

    test "raises ArgumentError if the second argument is not a proper list" do
      assert_error ArgumentError, build_argument_error_msg(2, "not a proper list"), fn ->
        :erlang.float_to_binary(@input_above_10, [:compact | {:decimals, 4}])
      end
    end

    test "raises ArgumentError if the second argument has invalid option in list" do
      assert_error ArgumentError, build_argument_error_msg(2, "invalid option in list"), fn ->
        :erlang.float_to_binary(@input_above_10, [:abc])
      end
    end
  end

  # Delegates to float_to_binary/2, only need to test opts passthrough and codepoint conversion
  describe "float_to_list/2" do
    test "returns a list of character code points" do
      result = :erlang.float_to_list(2.0, [:short])

      # [50, 46, 48] == ~c"2.0"
      assert result == [50, 46, 48]
    end
  end

  describe "floor/1" do
    test "rounds positive float with fractional part down" do
      assert :erlang.floor(1.23) == 1
    end

    test "rounds negative float with fractional part down" do
      assert :erlang.floor(-1.23) == -2
    end

    test "keeps positive float without fractional part unchanged" do
      assert :erlang.floor(1.0) == 1
    end

    test "keeps negative float without fractional part unchanged" do
      assert :erlang.floor(-1.0) == -1
    end

    test "keeps signed negative zero float unchanged" do
      assert :erlang.floor(-0.0) == 0
    end

    test "keeps signed positive zero float unchanged" do
      assert :erlang.floor(+0.0) == 0
    end

    test "keeps unsigned zero float unchanged" do
      assert :erlang.floor(0.0) == 0
    end

    test "keeps positive integer unchanged" do
      assert :erlang.floor(1) == 1
    end

    test "keeps negative integer unchanged" do
      assert :erlang.floor(-1) == -1
    end

    test "keeps zero integer unchanged" do
      assert :erlang.floor(0) == 0
    end

    test "raises ArgumentError if the argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:erlang, :floor, [:abc]}
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

  describe "insert_element/3" do
    test "inserts the given value into an empty tuple" do
      assert :erlang.insert_element(1, {}, :a) === {:a}
    end

    test "inserts the given value at the beginning of a one-element tuple" do
      assert :erlang.insert_element(1, {1}, :a) === {:a, 1}
    end

    test "inserts the given value at the end of a one-element tuple" do
      assert :erlang.insert_element(2, {1}, :a) === {1, :a}
    end

    test "inserts the given value at the beginning of a multi-element tuple" do
      assert :erlang.insert_element(1, {1, 2}, :a) === {:a, 1, 2}
    end

    test "inserts the given value into the middle of a multi-element tuple" do
      assert :erlang.insert_element(2, {1, 2}, :a) === {1, :a, 2}
    end

    test "inserts the given value at the end of a multi-element tuple" do
      assert :erlang.insert_element(3, {1, 2}, :a) === {1, 2, :a}
    end

    test "raises ArgumentError if the first argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an integer"),
                   {:erlang, :insert_element, [:b, {1, 2}, :a]}
    end

    test "raises ArgumentError if the second argument is not a tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a tuple"),
                   {:erlang, :insert_element, [1, :b, :a]}
    end

    test "raises ArgumentError if the index is larger than the size of the tuple plus one" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "out of range"),
                   {:erlang, :insert_element, [4, {1, 2}, :a]}
    end

    test "raises ArgumentError if the index is not positive" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "out of range"),
                   {:erlang, :insert_element, [0, {1, 2}, :a]}
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

  describe "integer_to_list/1" do
    test "delegates to integer_to_list/2 with base 10" do
      assert :erlang.integer_to_list(123) == :erlang.integer_to_list(123, 10)
    end
  end

  describe "integer_to_list/2" do
    test "base 2 (min allowed value for base param)" do
      assert :erlang.integer_to_list(123, 2) == ~c"1111011"
    end

    test "base 10" do
      assert :erlang.integer_to_list(123, 10) == ~c"123"
    end

    test "base 36 (max allowed value for base param)" do
      assert :erlang.integer_to_list(123, 36) == ~c"3F"
    end

    test "negative integer, base 10" do
      assert :erlang.integer_to_list(-123, 10) == ~c"-123"
    end

    test "negative integer, base other than 10" do
      assert :erlang.integer_to_list(-123, 16) == ~c"-7B"
    end

    test "zero, base 10" do
      assert :erlang.integer_to_list(0, 10) == ~c"0"
    end

    test "zero, base other than 10" do
      assert :erlang.integer_to_list(0, 16) == ~c"0"
    end

    test "raises ArgumentError when the first argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an integer"),
                   {:erlang, :integer_to_list, [3.14, 10]}
    end

    test "raises ArgumentError when base is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :integer_to_list, [123, 3.14]}
    end

    test "raises ArgumentError for base < 2" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :integer_to_list, [123, 1]}
    end

    test "raises ArgumentError for base > 36" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :integer_to_list, [123, 37]}
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

  describe "is_map_key/2" do
    test "returns true if the given map has the given key" do
      assert :erlang.is_map_key(:b, %{a: 1, b: 2}) == true
    end

    test "returns false if the given map doesn't have the given key" do
      assert :erlang.is_map_key(:c, %{a: 1, b: 2}) == false
    end

    test "raises BadMapError if the second argument is not a map" do
      assert_error BadMapError, "expected a map, got: :abc", {:erlang, :is_map_key, [:x, :abc]}
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

  describe "list_to_integer/1" do
    test "delegates to list_to_integer/2 with base 10" do
      assert :erlang.list_to_integer([49, 50, 51]) ==
               :erlang.list_to_integer([49, 50, 51], 10)
    end
  end

  describe "list_to_integer/2" do
    test "base 2" do
      # 0b1010 = 10
      assert :erlang.list_to_integer([49, 48, 49, 48], 2) == 10
    end

    test "base 10" do
      assert :erlang.list_to_integer([49, 50, 51], 10) == 123
    end

    test "base 16" do
      # 0x3AF = 943
      assert :erlang.list_to_integer([51, 65, 70], 16) == 943
    end

    test "base 36" do
      # "YZ" = 1259
      assert :erlang.list_to_integer([89, 90], 36) == 1259
    end

    test "positive integer with plus sign" do
      assert :erlang.list_to_integer([43, 49, 50, 51], 10) == 123
    end

    test "negative integer" do
      assert :erlang.list_to_integer([45, 49, 50, 51], 10) == -123
    end

    test "zero" do
      assert :erlang.list_to_integer([48], 10) == 0
    end

    test "lowercase letters" do
      assert :erlang.list_to_integer([97, 98, 99, 100], 16) == 43_981
    end

    test "uppercase letters" do
      assert :erlang.list_to_integer([65, 66, 67, 68], 16) == 43_981
    end

    test "mixed case letters" do
      assert :erlang.list_to_integer([97, 66, 99, 68], 16) == 43_981
    end

    test "leading zeros" do
      assert :erlang.list_to_integer([48, 48, 49, 50, 51], 10) == 123
    end

    test "very large (above Number.MAX_SAFE_INTEGER) base 10 integer" do
      # Number.MAX_SAFE_INTEGER = 9007199254740991
      large_list = List.duplicate(57, 30)
      large_int = :erlang.list_to_integer(large_list, 10)

      assert large_int == 999_999_999_999_999_999_999_999_999_999
    end

    test "very large (below Number.MIN_SAFE_INTEGER) negative base 10 integer" do
      # Number.MIN_SAFE_INTEGER = -9007199254740991
      large_list = List.duplicate(57, 30)
      large_int = :erlang.list_to_integer([?- | large_list], 10)

      assert large_int == -999_999_999_999_999_999_999_999_999_999
    end

    test "very large (above Number.MAX_SAFE_INTEGER) integer with letter digits" do
      # Number.MAX_SAFE_INTEGER = 9007199254740991
      large_list = List.duplicate(?F, 20)
      large_int = :erlang.list_to_integer(large_list, 16)

      assert large_int == 0xFFFFFFFFFFFFFFFFFFFF
    end

    test "very large (below Number.MIN_SAFE_INTEGER) negative integer with letter digits" do
      # Number.MIN_SAFE_INTEGER = -9007199254740991
      large_list = List.duplicate(?F, 20)
      large_int = :erlang.list_to_integer([?- | large_list], 16)

      assert large_int == -0xFFFFFFFFFFFFFFFFFFFF
    end

    test "raises ArgumentError if the first argument is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   {:erlang, :list_to_integer, [:abc, 10]}
    end

    test "raises ArgumentError if the first argument is not a proper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a proper list"),
                   {:erlang, :list_to_integer, [[49, 50 | 51], 10]}
    end

    test "raises ArgumentError if list is empty" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   {:erlang, :list_to_integer, [[], 10]}
    end

    test "raises ArgumentError if list contains non-integer element" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   {:erlang, :list_to_integer, [[49, :abc, 51], 10]}
    end

    test "raises ArgumentError if list contains characters outside of the alphabet" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   {:erlang, :list_to_integer, [[50], 2]}
    end

    test "raises ArgumentError on sign in non-leading position" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   {:erlang, :list_to_integer, [[49, 50, 45, 51], 10]}
    end

    test "raises ArgumentError on multiple signs" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   {:erlang, :list_to_integer, [[43, 45, 49, 50, 51], 10]}
    end

    test "raises ArgumentError on minus sign only" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   {:erlang, :list_to_integer, [[45], 10]}
    end

    test "raises ArgumentError on plus sign only" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of an integer"),
                   {:erlang, :list_to_integer, [[43], 10]}
    end

    test "raises ArgumentError if the second argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :list_to_integer, [[49], :abc]}
    end

    test "raises ArgumentError if base is less than 2" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :list_to_integer, [[49, 50, 51], 1]}
    end

    test "raises ArgumentError if base is greater than 36" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not an integer in the range 2 through 36"),
                   {:erlang, :list_to_integer, [[49, 50, 51], 37]}
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

  describe "list_to_ref/1" do
    test "valid textual representation of reference for local node" do
      assert :erlang.list_to_ref(~c"#Ref<0.1.2.3>") == ref("0.1.2.3")
    end

    # Not testable in a practical way
    # test "valid textual representation of reference for remote node"

    test "invalid textual representation of reference (missing parts)" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a reference"),
                   {:erlang, :list_to_ref, [~c"#Ref<0.1>"]}
    end

    test "non-existent local incarnation ID" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a reference"),
                   {:erlang, :list_to_ref, [~c"#Ref<999.1.2.3>"]}
    end

    test "not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   {:erlang, :list_to_ref, [123]}
    end

    test "not a proper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   {:erlang, :list_to_ref, [[123 | 124]]}
    end

    test "a list that contains a non-integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a reference"),
                   # 36 = $, 82 = R
                   {:erlang, :list_to_ref, [[36, :abc, 82]]}
    end

    test "a list that contains an invalid codepoint" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a textual representation of a reference"),
                   # 36 = $, 82 = R
                   {:erlang, :list_to_ref, [[36, 255, 82]]}
    end
  end

  describe "list_to_tuple/1" do
    test "non-empty list" do
      assert :erlang.list_to_tuple([1, 2, 3]) == {1, 2, 3}
    end

    test "empty list" do
      assert :erlang.list_to_tuple([]) == {}
    end

    test "raises ArgumentError if the argument is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   {:erlang, :list_to_tuple, [:abc]}
    end

    test "raises ArgumentError if the argument is an improper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   {:erlang, :list_to_tuple, [[1, 2 | 3]]}
    end
  end

  describe "localtime/0" do
    test "returns a tuple with date and time" do
      assert {{year, month, day}, {hour, minute, second}} = :erlang.localtime()

      assert year in 1970..2100
      assert month in 1..12
      assert day in 1..31
      assert hour in 0..23
      assert minute in 0..59
      assert second in 0..59
    end
  end

  describe "make_ref/0" do
    test "returns a reference" do
      result = :erlang.make_ref()

      assert is_reference(result)
    end

    test "consecutive calls return unique references" do
      ref1 = :erlang.make_ref()
      ref2 = :erlang.make_ref()

      assert ref1 != ref2
    end
  end

  describe "make_tuple/2" do
    test "creates tuple of the given size with all elements set to the given value" do
      assert :erlang.make_tuple(3, :a) === {:a, :a, :a}
    end

    test "creates an empty tuple when arity is zero" do
      assert :erlang.make_tuple(0, :a) === {}
    end

    test "raises ArgumentError when arity is negative" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "out of range"),
                   {:erlang, :make_tuple, [-1, :a]}
    end

    test "raises ArgumentError when arity is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "out of range"),
                   {:erlang, :make_tuple, [2.0, :a]}
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

  describe "pid_to_list/1" do
    test "single digit segments" do
      pid = pid("0.1.2")

      assert :erlang.pid_to_list(pid) == ~c"<0.1.2>"
    end

    test "multi-digit segments" do
      pid = pid("0.11.222")

      assert :erlang.pid_to_list(pid) == ~c"<0.11.222>"
    end

    test "not a pid" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a pid"),
                   {:erlang, :pid_to_list, [123]}
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

  describe "setelement/3" do
    test "replaces a middle element" do
      assert :erlang.setelement(2, {1, 2, 3}, :a) === {1, :a, 3}
    end

    test "replaces the first element" do
      assert :erlang.setelement(1, {1, 2}, :a) === {:a, 2}
    end

    test "replaces the last element" do
      assert :erlang.setelement(2, {1, 2}, :a) === {1, :a}
    end

    test "raises ArgumentError if the first argument is not an integer" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not an integer"),
                   {:erlang, :setelement, [:b, {1, 2}, :a]}
    end

    test "raises ArgumentError if the second argument is not a tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(2, "not a tuple"),
                   {:erlang, :setelement, [1, :b, :a]}
    end

    test "raises ArgumentError if the index is larger than the size of the tuple" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "out of range"),
                   {:erlang, :setelement, [3, {1, 2}, :a]}
    end

    test "raises ArgumentError if the index is not positive" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "out of range"),
                   {:erlang, :setelement, [0, {1, 2}, :a]}
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
    test "drops fractional part of positive float" do
      assert :erlang.trunc(1.23) == 1
    end

    test "drops fractional part of negative float" do
      assert :erlang.trunc(-1.23) == -1
    end

    test "drops fractional part of negative zero float" do
      assert :erlang.trunc(-0.0) == 0
    end

    test "drops fractional part of positive zero float" do
      assert :erlang.trunc(+0.0) == 0
    end

    test "drops fractional part of unsigned zero float" do
      assert :erlang.trunc(0.0) == 0
    end

    test "keeps positive integer unchanged" do
      assert :erlang.trunc(1) == 1
    end

    test "keeps negative integer unchanged" do
      assert :erlang.trunc(-1) == -1
    end

    test "keeps zero integer unchanged" do
      assert :erlang.trunc(0) == 0
    end

    test "demonstrates floating-point precision limits for large numbers" do
      assert :erlang.trunc(36_028_797_018_963_969.0) == 36_028_797_018_963_968
    end

    test "raises ArgumentError if the argument is not a number" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a number"),
                   {:erlang, :trunc, [:abc]}
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

  describe "unique_integer/0" do
    test "returns a unique integer each time it is called" do
      integer_1 = :erlang.unique_integer()
      assert is_integer(integer_1)

      integer_2 = :erlang.unique_integer()
      assert is_integer(integer_2)

      assert integer_1 != integer_2
    end
  end

  describe "unique_integer/1" do
    test "returns a unique integer each time it is called with empty modifier list" do
      integer_1 = :erlang.unique_integer([])
      assert is_integer(integer_1)

      integer_2 = :erlang.unique_integer([])
      assert is_integer(integer_2)

      assert integer_1 != integer_2
    end

    test "returns a unique integer with positive modifier" do
      integer_1 = :erlang.unique_integer([:positive])
      assert is_integer(integer_1)

      integer_2 = :erlang.unique_integer([:positive])
      assert is_integer(integer_2)

      assert integer_1 != integer_2
    end

    test "returns a unique integer with monotonic modifier" do
      integer_1 = :erlang.unique_integer([:monotonic])
      assert is_integer(integer_1)

      integer_2 = :erlang.unique_integer([:monotonic])
      assert is_integer(integer_2)

      assert integer_1 != integer_2
    end

    test "returns a unique integer with both positive and monotonic modifiers" do
      integer_1 = :erlang.unique_integer([:positive, :monotonic])
      assert is_integer(integer_1)

      integer_2 = :erlang.unique_integer([:positive, :monotonic])
      assert is_integer(integer_2)

      assert integer_1 != integer_2
    end

    test "raises ArgumentError if the argument is not a list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a list"),
                   {:erlang, :unique_integer, [:abc]}
    end

    test "raises ArgumentError if the argument is not a proper list" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "not a proper list"),
                   {:erlang, :unique_integer, [[:positive | :abc]]}
    end

    test "raises ArgumentError if the modifier is not an atom" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid modifier"),
                   {:erlang, :unique_integer, [[123]]}
    end

    test "raises ArgumentError if the modifier is not a valid modifier" do
      assert_error ArgumentError,
                   build_argument_error_msg(1, "invalid modifier"),
                   {:erlang, :unique_integer, [[:invalid]]}
    end
  end

  describe "xor/2" do
    test "true xor false" do
      assert :erlang.xor(true, false) == true
    end

    test "false xor true" do
      assert :erlang.xor(false, true) == true
    end

    test "true xor true" do
      assert :erlang.xor(true, true) == false
    end

    test "false xor false" do
      assert :erlang.xor(false, false) == false
    end

    test "raises ArgumentError if the first argument is not a boolean" do
      assert_error ArgumentError, "argument error", {:erlang, :xor, [:abc, true]}
    end

    test "raises ArgumentError if the second argument is not a boolean" do
      assert_error ArgumentError, "argument error", {:erlang, :xor, [true, :abc]}
    end
  end
end
