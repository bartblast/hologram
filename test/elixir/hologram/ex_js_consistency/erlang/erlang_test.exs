defmodule Hologram.ExJsConsistency.Erlang.ErlangTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erlang_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  describe ">=/2" do
    test "returns true when left float argument is greater than right float argument" do
      assert :erlang.>=(5.6, 3.2) == true
    end

    test "returns true when left float argument is greater than right integer argument" do
      assert :erlang.>=(5.6, 3) == true
    end

    test "returns true when left integer argument is greater than right float argument" do
      assert :erlang.>=(5, 3.2) == true
    end

    test "returns true when left integer argument is greater than right integer argument" do
      assert :erlang.>=(5, 3) == true
    end

    test "returns true when left float argument is equal to right float argument" do
      assert :erlang.>=(3.0, 3.0) == true
    end

    test "returns true when left float argument is equal to right integer argument" do
      assert :erlang.>=(3.0, 3) == true
    end

    test "returns true when left integer argument is equal to right float argument" do
      assert :erlang.>=(3, 3.0) == true
    end

    test "returns true when left integer argument is equal to right integer argument" do
      assert :erlang.>=(3, 3) == true
    end

    test "returns false when left float argument is smaller than right float argument" do
      assert :erlang.>=(3.2, 5.6) == false
    end

    test "returns false when left float argument is smaller than right integer argument" do
      assert :erlang.>=(3.2, 5) == false
    end

    test "returns false when left integer argument is smaller than right float argument" do
      assert :erlang.>=(3, 5.6) == false
    end

    test "returns false when left integer argument is smaller than right integer argument" do
      assert :erlang.>=(3, 5) == false
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
end
