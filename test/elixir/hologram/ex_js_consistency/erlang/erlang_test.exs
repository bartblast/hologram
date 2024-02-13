defmodule Hologram.ExJsConsistency.Erlang.ErlangTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erlang_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  describe "*/2" do
    test "multiplies integer by integer" do
      assert :erlang.*(2, 3) === 6
    end

    test "multiplies integer by float" do
      assert :erlang.*(2, 3.0) === 6.0
    end

    test "multiplies float by integer" do
      assert :erlang.*(2.0, 3) === 6.0
    end

    test "miltiplies float by float" do
      assert :erlang.*(2.0, 3.0) === 6.0
    end

    test "raises ArithmeticError if the first argument is not a number" do
      assert_raise ArithmeticError, "bad argument in arithmetic expression", fn ->
        :erlang.*(build_value(:abc), 123)
      end
    end

    test "raises ArithmeticError if the second argument is not a number" do
      assert_raise ArithmeticError, "bad argument in arithmetic expression", fn ->
        :erlang.*(123, build_value(:abc))
      end
    end
  end

  describe "+/2" do
    test "adds integer and integer" do
      assert :erlang.+(1, 2) === 3
    end

    test "adds integer and float" do
      assert :erlang.+(1, 2.0) === 3.0
    end

    test "adds float and integer" do
      assert :erlang.+(1.0, 2) === 3.0
    end

    test "adds float and float" do
      assert :erlang.+(1.0, 2.0) === 3.0
    end

    test "raises ArithmeticError if the first argument is not a number" do
      assert_raise ArithmeticError, "bad argument in arithmetic expression", fn ->
        :erlang.+(build_value(:abc), 123)
      end
    end

    test "raises ArithmeticError if the second argument is not a number" do
      assert_raise ArithmeticError, "bad argument in arithmetic expression", fn ->
        :erlang.+(123, build_value(:abc))
      end
    end
  end

  describe "-/2" do
    test "subtracts integer and integer" do
      assert :erlang.-(3, 1) === 2
    end

    test "subtracts integer and float" do
      assert :erlang.-(3, 1.0) === 2.0
    end

    test "subtracts float and integer" do
      assert :erlang.-(3.0, 1) === 2.0
    end

    test "subtracts float and float" do
      assert :erlang.-(3.0, 1.0) === 2.0
    end

    test "raises ArithmeticError if the first argument is not a number" do
      assert_raise ArithmeticError, "bad argument in arithmetic expression", fn ->
        :erlang.-(build_value(:abc), 123)
      end
    end

    test "raises ArithmeticError if the second argument is not a number" do
      assert_raise ArithmeticError, "bad argument in arithmetic expression", fn ->
        :erlang.-(123, build_value(:abc))
      end
    end
  end

  describe "/=/2" do
    test "non-number == non-number" do
      assert :erlang."/="(:abc, :abc) == false
    end

    test "non-number != non-number" do
      assert :erlang."/="(:abc, :xyz) == true
    end

    test "integer == integer" do
      assert :erlang."/="(1, 1) == false
    end

    test "integer != integer" do
      assert :erlang."/="(1, 2) == true
    end

    test "integer == float" do
      assert :erlang."/="(1, 1.0) == false
    end

    test "integer != float" do
      assert :erlang."/="(1, 2.0) == true
    end

    test "integer != non-number" do
      assert :erlang."/="(1, :abc) == true
    end

    test "float == float" do
      assert :erlang."/="(1.0, 1.0) == false
    end

    test "float != float" do
      assert :erlang."/="(1.0, 2.0) == true
    end

    test "float == integer" do
      assert :erlang."/="(1, 1.0) == false
    end

    test "float != integer" do
      assert :erlang."/="(1.0, 2) == true
    end

    test "float != non-number" do
      assert :erlang."/="(1.0, :abc) == true
    end
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

    test "atom < atom" do
      assert :erlang.<(:a, :b) == true
    end

    test "float < atom (always)" do
      assert :erlang.<(1.0, :a) == true
    end

    test "float < float" do
      assert :erlang.<(1.0, 2.0) == true
    end

    test "float < integer" do
      assert :erlang.<(1.0, 2) == true
    end

    test "integer < atom (always)" do
      assert :erlang.<(1, :a) == true
    end

    test "integer < float" do
      assert :erlang.<(1, 2.0) == true
    end

    test "integer < integer" do
      assert :erlang.<(1, 2) == true
    end

    test "atom > atom" do
      assert :erlang.<(:b, :a) == false
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

    # // TODO: reference, function, port, pid, tuple, map, list, bitstring
  end

  describe "=:=/2" do
    test "non-number == non-number" do
      assert :erlang."=:="(:abc, :abc) == true
    end

    test "non-number != non-number" do
      assert :erlang."=:="(:abc, :xyz) == false
    end

    test "integer == integer" do
      assert :erlang."=:="(1, 1) == true
    end

    test "integer != integer" do
      assert :erlang."=:="(1, 2) == false
    end

    test "integer == float" do
      assert :erlang."=:="(1, 1.0) == false
    end

    test "integer != float" do
      assert :erlang."=:="(1, 2.0) == false
    end

    test "integer != non-number" do
      assert :erlang."=:="(1, :abc) == false
    end

    test "float == float" do
      assert :erlang."=:="(1.0, 1.0) == true
    end

    test "float != float" do
      assert :erlang."=:="(1.0, 2.0) == false
    end

    test "float == integer" do
      assert :erlang."=:="(1, 1.0) == false
    end

    test "float != integer" do
      assert :erlang."=:="(1.0, 2) == false
    end

    test "float != non-number" do
      assert :erlang."=:="(1.0, :abc) == false
    end
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

    test "atom < atom" do
      assert :erlang."=<"(:a, :b) == true
    end

    test "float < atom (always)" do
      assert :erlang."=<"(1.0, :a) == true
    end

    test "float < float" do
      assert :erlang."=<"(1.0, 2.0) == true
    end

    test "float < integer" do
      assert :erlang."=<"(1.0, 2) == true
    end

    test "integer < atom (always)" do
      assert :erlang."=<"(1, :a) == true
    end

    test "integer < float" do
      assert :erlang."=<"(1, 2.0) == true
    end

    test "integer < integer" do
      assert :erlang."=<"(1, 2) == true
    end

    test "atom > atom" do
      assert :erlang."=<"(:b, :a) == false
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

    # // TODO: reference, function, port, pid, tuple, map, list, bitstring
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

    test "atom < atom" do
      assert :erlang.>(:a, :b) == false
    end

    test "float < atom (always)" do
      assert :erlang.>(1.0, :a) == false
    end

    test "float < float" do
      assert :erlang.>(1.0, 2.0) == false
    end

    test "float < integer" do
      assert :erlang.>(1.0, 2) == false
    end

    test "integer < atom (always)" do
      assert :erlang.>(1, :a) == false
    end

    test "integer < float" do
      assert :erlang.>(1, 2.0) == false
    end

    test "integer < integer" do
      assert :erlang.>(1, 2) == false
    end

    test "atom > atom" do
      assert :erlang.>(:b, :a) == true
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

    # // TODO: reference, function, port, pid, tuple, map, list, bitstring
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

    test "atom < atom" do
      assert :erlang.>=(:a, :b) == false
    end

    test "float < atom (always)" do
      assert :erlang.>=(1.0, :a) == false
    end

    test "float < float" do
      assert :erlang.>=(1.0, 2.0) == false
    end

    test "float < integer" do
      assert :erlang.>=(1.0, 2) == false
    end

    test "integer < atom (always)" do
      assert :erlang.>=(1, :a) == false
    end

    test "integer < float" do
      assert :erlang.>=(1, 2.0) == false
    end

    test "integer < integer" do
      assert :erlang.>=(1, 2) == false
    end

    test "atom > atom" do
      assert :erlang.>=(:b, :a) == true
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

    # // TODO: reference, function, port, pid, tuple, map, list, bitstring
  end

  describe "andalso/2" do
    test "returns false if the first argument is false" do
      assert :erlang.andalso(false, :abc) == false
    end

    test "returns the second argument if the first argument is true" do
      assert :erlang.andalso(true, :abc) == :abc
    end

    test "doesn't evaluate the second argument if the first argument is false" do
      assert :erlang.andalso(false, raise("impossible")) == false
    end

    test "raises ArgumentError if the first argument is not a boolean" do
      assert_raise ArgumentError, "argument error: nil", fn ->
        :erlang.andalso(nil, true)
      end
    end
  end

  describe "atom_to_binary/1" do
    test "converts atom to (binary) bitstring" do
      assert :erlang.atom_to_binary(:abc) == <<"abc">>
    end

    test "raises ArgumentError if the argument is not an atom" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not an atom\n",
                   fn ->
                     # wrap the code with anonymous function to avoid compiler warnings
                     fun = fn x -> :erlang.atom_to_binary(x) end
                     fun.(123)
                   end
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
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not an atom\n",
                   fn ->
                     123
                     |> build_value()
                     |> :erlang.atom_to_list()
                   end
    end
  end

  test "binary_to_atom/1" do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    assert :erlang.binary_to_atom("全息图") == :erlang.binary_to_atom("全息图", :utf8)
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
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not a binary\n",
                   fn ->
                     <<1::1, 0::1, 1::1>>
                     |> build_value()
                     # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
                     |> :erlang.binary_to_atom(:utf8)
                   end
    end

    test "raises ArgumentErorr if the first argument is not a bitstring" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not a binary\n",
                   fn ->
                     :abc
                     |> build_value()
                     # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
                     |> :erlang.binary_to_atom(:utf8)
                   end
    end
  end

  describe "bit_size/1" do
    test "bitstring" do
      assert bit_size(<<2::7>>) == 7
    end

    test "not bitstring" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not a bitstring\n",
                   fn ->
                     :abc
                     |> build_value()
                     |> bit_size()
                   end
    end
  end

  describe "element/2" do
    test "returns the element at the one-based index in the tuple" do
      assert :erlang.element(2, {5, 6, 7}) == 6
    end

    test "raises ArgumentError if the first argument is not an integer" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not an integer\n",
                   fn ->
                     :erlang.element(build_value(:abc), {5, 6, 7})
                   end
    end

    test "raises ArgumentError if the second argument is not a tuple" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 2nd argument: not a tuple\n",
                   fn ->
                     :erlang.element(1, build_value(:abc))
                   end
    end

    test "raises ArgumentError if the given index is greater than the number of elements in the tuple" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: out of range\n",
                   fn ->
                     :erlang.element(build_value(10), {5, 6, 7})
                   end
    end

    test "raises ArgumentError if the given index is smaller than 1" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: out of range\n",
                   fn ->
                     :erlang.element(build_value(0), {5, 6, 7})
                   end
    end
  end

  describe "integer_to_binary/1" do
    assert :erlang.integer_to_binary(123_123) == :erlang.integer_to_binary(123_123, 10)
  end

  describe "integer_to_binary/2" do
    test "positive integer, base = 1" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 2nd argument: not an integer in the range 2 through 36\n",
                   fn ->
                     :erlang.integer_to_binary(123_123, 1)
                   end
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
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 2nd argument: not an integer in the range 2 through 36\n",
                   fn ->
                     :erlang.integer_to_binary(123_123, 37)
                   end
    end

    test "negative integer" do
      assert :erlang.integer_to_binary(-123_123, 16) == "-1E0F3"
    end

    test "1st argument (integer) is not an integer" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not an integer\n",
                   fn ->
                     :erlang.integer_to_binary(:abc, 16)
                   end
    end

    test "2nd argument (base) is not an integer" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 2nd argument: not an integer in the range 2 through 36\n",
                   fn ->
                     :erlang.integer_to_binary(123_123, :abc)
                   end
    end
  end

  describe "is_binary/1" do
    test "returns true if the term is a binary bitsting" do
      assert :erlang.is_binary("abc") == true
    end

    test "returns false if the term is a non-binary bitstring" do
      assert :erlang.is_binary(<<2::size(7)>>) == false
    end

    test "returns false if the term is not a bitstring" do
      assert :erlang.is_binary(:abc) == false
    end
  end

  describe "is_bitstring/1" do
    test "returns true if the term is a bistring" do
      assert :erlang.is_bitstring(<<2::size(7)>>) == true
    end

    test "returns false if the term is not a bitstring" do
      assert :erlang.is_bitstring(:abc) == false
    end
  end

  describe "is_function/1" do
    test "returns true if the term is an anonymous function" do
      assert :erlang.is_function(fn x -> x end) == true
    end

    test "returns false if the term is not an anonymous function" do
      assert :erlang.is_function(:abc) == false
    end
  end

  describe "is_function/2" do
    test "returns true if the term is an anonymous function with the given arity" do
      term = fn x, y, z -> {x, y, z} end
      assert :erlang.is_function(term, 3) == true
    end

    test "returns false if the term is an anonymous function with a different arity" do
      term = fn x, y, z -> {x, y, z} end
      assert :erlang.is_function(term, 4) == false
    end

    test "returns false if the term is not an anonymous function" do
      assert :erlang.is_function(:abc, 3) == false
    end
  end

  describe "is_map/1" do
    test "returns true if the term is a map" do
      assert :erlang.is_map(%{a: 1, b: 2}) == true
    end

    test "returns false if the term is not a map" do
      assert :erlang.is_map(:abc) == false
    end
  end

  describe "is_pid/1" do
    test "returns true if the term is a pid" do
      assert :erlang.is_pid(self()) == true
    end

    test "returns false if the term is not a pid" do
      assert :erlang.is_pid(:abc) == false
    end
  end

  describe "is_port/1" do
    test "returns true if the term is a port" do
      assert :erlang.is_port(port("0.11")) == true
    end

    test "returns false if the term is not a port" do
      assert :erlang.is_port(:abc) == false
    end
  end

  describe "is_reference/1" do
    test "returns true if the term is a reference" do
      assert :erlang.is_reference(make_ref()) == true
    end

    test "returns false if the term is not a reference" do
      assert :erlang.is_reference(:abc) == false
    end
  end

  describe "is_tuple/1" do
    test "returns true if the term is a tuple" do
      assert :erlang.is_tuple({1, 2}) == true
    end

    test "returns false if the term is not a tuple" do
      assert :erlang.is_tuple(:abc) == false
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
      assert :erlang.orelse(true, raise("impossible")) == true
    end

    test "raises ArgumentError if the first argument is not a boolean" do
      assert_raise ArgumentError, "argument error: nil", fn ->
        :erlang.orelse(nil, true)
      end
    end
  end

  describe "tuple_to_list/1" do
    test "returns a list corresponding to the given tuple" do
      assert :erlang.tuple_to_list({1, 2, 3}) == [1, 2, 3]
    end

    test "raises ArgumentError if the argument is not a tuple" do
      assert_raise ArgumentError,
                   "errors were found at the given arguments:\n\n  * 1st argument: not a tuple\n",
                   fn ->
                     :erlang.tuple_to_list(build_value(:abc))
                   end
    end
  end
end
