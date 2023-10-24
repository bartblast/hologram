defmodule Hologram.ExJsConsistency.Erlang.ErlangTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/erlang_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  describe ":erlang.is_bitstring/1" do
    test "returns true if the term is a bistring" do
      assert :erlang.is_bitstring(<<2::size(7)>>) == true
    end

    test "returns false if the term is not a bitstring" do
      assert :erlang.is_bitstring(:abc) == false
    end
  end

  describe ":erlang.is_map/1" do
    test "returns true if the term is a map" do
      assert :erlang.is_map(%{a: 1, b: 2}) == true
    end

    test "returns false if the term is not a map" do
      assert :erlang.is_map(:abc) == false
    end
  end

  describe ":erlang.is_tuple/1" do
    test "returns true if the term is a tuple" do
      assert :erlang.is_tuple({1, 2}) == true
    end

    test "returns false if the term is not a tuple" do
      assert :erlang.is_tuple(:abc) == false
    end
  end
end
