defmodule Hologram.Compiler.DataFlow.ModelsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.Models

  test "listed_elixir_mfas/0" do
    missing =
      Enum.reject(listed_elixir_mfas(), fn {module, function, arity} ->
        Code.ensure_loaded?(module) and function_exported?(module, function, arity)
      end)

    assert missing == []
  end

  describe "summary/1" do
    test "Erlang function that never returns" do
      assert summary({:erlang, :error, 1}) == MapSet.new()
      assert summary({:erlang, :throw, 1}) == MapSet.new()
    end

    test "Erlang function returning a primitive" do
      assert summary({:erlang, :+, 2}) == MapSet.new([:prim])
      assert summary({:erlang, :iolist_to_binary, 1}) == MapSet.new([:prim])
    end

    test "function of an Erlang module returning primitives" do
      assert summary({:binary, :split, 2}) == MapSet.new([:prim])
    end

    test "function of an Elixir module returning primitives" do
      assert summary({String, :split, 2}) == MapSet.new([:prim])
    end

    test "Elixir function returning a primitive" do
      assert summary({Enum, :join, 2}) == MapSet.new([:prim])
      assert summary({String.Chars, :to_string, 1}) == MapSet.new([:prim])
    end

    test "Erlang function of :erlang that can return what it is given" do
      assert summary({:erlang, :element, 2}) == nil
    end

    test "Elixir function that can return what it is given" do
      assert summary({Enum, :map, 2}) == nil
    end
  end
end
