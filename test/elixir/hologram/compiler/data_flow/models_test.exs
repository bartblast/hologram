defmodule Hologram.Compiler.DataFlow.ModelsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.Models

  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.ShapeSet
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  @struct_1 {:struct, Struct1, ShapeSet.new()}

  # What a call of the modelled function with arguments of the given shapes gives.
  defp call_model(mfa, args) do
    mfa
    |> summary()
    |> DataFlow.apply_summary(Enum.map(args, &ShapeSet.new/1))
  end

  test "listed_elixir_mfas/0" do
    missing =
      Enum.reject(listed_elixir_mfas(), fn {module, function, arity} ->
        Code.ensure_loaded?(module) and function_exported?(module, function, arity)
      end)

    assert missing == []
  end

  describe "summary/1" do
    test "Erlang function that never returns" do
      assert summary({:erlang, :error, 1}) == ShapeSet.new()
      assert summary({:erlang, :throw, 1}) == ShapeSet.new()
    end

    test "Erlang function returning a primitive" do
      assert summary({:erlang, :+, 2}) == ShapeSet.new([:prim])
      assert summary({:erlang, :iolist_to_binary, 1}) == ShapeSet.new([:prim])
    end

    test "function of an Erlang module returning primitives" do
      assert summary({:binary, :split, 2}) == ShapeSet.new([:prim])
    end

    test "function of an Elixir module returning primitives" do
      assert summary({String, :split, 2}) == ShapeSet.new([:prim])
    end

    test "Elixir function returning a primitive" do
      assert summary({Enum, :join, 2}) == ShapeSet.new([:prim])
      assert summary({String.Chars, :to_string, 1}) == ShapeSet.new([:prim])
    end

    test "Erlang function without a model" do
      assert summary({:erlang, :send, 2}) == nil
    end

    test "Elixir function that can return what it is given" do
      assert summary({Enum, :map, 2}) == nil
    end

    test "Erlang function taking a value out of what it is given" do
      assert call_model({:maps, :get, 2}, [[{:atom, :a}], [{:map, ShapeSet.new([@struct_1])}]]) ==
               ShapeSet.new([@struct_1])

      assert call_model({:erlang, :element, 2}, [[:prim], [{:tuple, [ShapeSet.new([@struct_1])]}]]) ==
               ShapeSet.new([@struct_1])
    end

    test "Erlang function putting what it is given in a new value" do
      args = [[{:atom, :a}], [@struct_1], [{:map, ShapeSet.new()}]]

      assert call_model({:maps, :put, 3}, args) ==
               ShapeSet.new([{:map, ShapeSet.new([{:atom, :a}, @struct_1])}])
    end

    test "Erlang function calling a function it is given" do
      ref = {{Struct1, :fun, 0}, 1}
      fun = {:fun, ref, ShapeSet.new([{:tuple, [ShapeSet.new([{:arg, ref, 0}])]}])}
      args = [[fun], [{:list, ShapeSet.new([@struct_1])}]]

      assert call_model({:lists, :map, 2}, args) ==
               ShapeSet.new([{:list, ShapeSet.new([{:tuple, [ShapeSet.new([@struct_1])]}])}])
    end

    test "Erlang function folding a function it is given over a list" do
      ref = {{Struct1, :fun, 2}, 1}

      pair =
        ShapeSet.new([{:tuple, [ShapeSet.new([{:arg, ref, 0}]), ShapeSet.new([{:arg, ref, 1}])]}])

      args = [[{:fun, ref, pair}], [{:atom, nil}], [{:list, ShapeSet.new([@struct_1])}]]

      round_1 =
        ShapeSet.new([
          {:atom, nil},
          {:tuple, [ShapeSet.new([@struct_1]), ShapeSet.new([{:atom, nil}])]}
        ])

      round_2 = ShapeSet.put(round_1, {:tuple, [ShapeSet.new([@struct_1]), round_1]})

      assert call_model({:lists, :foldl, 3}, args) == round_2
    end

    test "Hologram function that returns the server as it was" do
      args = [[{:struct, Server, ShapeSet.new()}], [:prim]]

      assert call_model({Server, :put_status, 2}, args) ==
               ShapeSet.new([{:struct, Server, ShapeSet.new()}])
    end

    test "a Hologram function that puts a value in the session has no model" do
      assert summary({Server, :put_session, 3}) == nil
    end
  end
end
