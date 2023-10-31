defmodule Hologram.ExJsConsistency.Erlang.ErlangTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erlang_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

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

    test "raises ArgumentError if the first argument is not a boolean" do
      assert_raise ArgumentError, "argument error: nil", fn ->
        :erlang.orelse(nil, true)
      end
    end
  end
end