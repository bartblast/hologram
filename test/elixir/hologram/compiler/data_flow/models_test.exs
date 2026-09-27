defmodule Hologram.Compiler.DataFlow.ModelsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.Models
  import Hologram.Test.DataFlowTrees

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.ShapeSet
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1

  @struct_1 {:struct, Struct1, %{}}

  # A map whose keys are not known, holding the shapes (see DataFlow.fields/0).
  defp rest_map(shapes) do
    fields =
      shapes
      |> tree_set()
      |> DataFlow.rest_fields()

    {:map, fields}
  end

  # The tree of what a call of the modelled function with arguments of the given shapes gives.
  defp call_model(mfa, args) do
    flow = DataFlow.start(PLT.start(), PLT.start())
    arg_sets = Enum.map(args, &ShapeSet.from_tree(tree_set(&1), flow.store))

    mfa
    |> summary()
    |> ShapeSet.from_tree(flow.store)
    |> DataFlow.apply_summary(arg_sets, flow)
    |> DataFlow.to_tree(flow)
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
      assert summary({:erlang, :error, 1}) == tree_set()
      assert summary({:erlang, :throw, 1}) == tree_set()
    end

    test "Erlang function returning a primitive" do
      assert summary({:erlang, :+, 2}) == tree_set([:prim])
      assert summary({:erlang, :iolist_to_binary, 1}) == tree_set([:prim])
    end

    test "function of an Erlang module returning primitives" do
      assert summary({:binary, :split, 2}) == tree_set([:prim])
    end

    test "function of an Elixir module returning primitives" do
      assert summary({String, :split, 2}) == tree_set([:prim])
    end

    test "Elixir function returning a primitive" do
      assert summary({Enum, :join, 2}) == tree_set([:prim])
      assert summary({String.Chars, :to_string, 1}) == tree_set([:prim])
    end

    test "Erlang function without a model" do
      assert summary({:erlang, :send, 2}) == nil
    end

    test "Elixir function that can return what it is given" do
      assert summary({Enum, :map, 2}) == nil
    end

    test "Erlang function taking a value out of what it is given" do
      assert call_model({:maps, :get, 2}, [[{:atom, :a}], [rest_map([@struct_1])]]) ==
               tree_set([@struct_1])

      assert call_model({:erlang, :element, 2}, [[:prim], [{:tuple, [tree_set([@struct_1])]}]]) ==
               tree_set([@struct_1])
    end

    test "Erlang function putting what it is given in a new value" do
      args = [[{:atom, :a}], [@struct_1], [{:map, %{}}]]

      # The key is a param, so the new pair goes to the rest (see DataFlow.fields/0); the map given
      # and the map with the pair are one map (see ShapeSet).
      assert call_model({:maps, :put, 3}, args) == tree_set([rest_map([{:atom, :a}, @struct_1])])
    end

    test "Erlang function giving back the struct it is given" do
      map = {:map, %{a: tree_set([:prim])}}

      assert call_model({:maps, :merge, 2}, [[@struct_1], [map]]) ==
               tree_set([@struct_1, map])

      assert call_model({:maps, :put, 3}, [[{:atom, :a}], [:prim], [@struct_1]]) ==
               tree_set([@struct_1, rest_map([{:atom, :a}, :prim])])

      assert call_model({:maps, :remove, 2}, [[{:atom, :a}], [@struct_1]]) ==
               tree_set([@struct_1])
    end

    test "Erlang function calling a function it is given" do
      ref = {{Struct1, :fun, 0}, 1}
      fun = {:fun, ref, tree_set([{:tuple, [tree_set([{:arg, ref, 0}])]}])}
      args = [[fun], [{:list, tree_set([@struct_1])}]]

      assert call_model({:lists, :map, 2}, args) ==
               tree_set([{:list, tree_set([{:tuple, [tree_set([@struct_1])]}])}])
    end

    test "Erlang function folding a function it is given over a list" do
      ref = {{Struct1, :fun, 2}, 1}

      pair =
        tree_set([{:tuple, [tree_set([{:arg, ref, 0}]), tree_set([{:arg, ref, 1}])]}])

      args = [[{:fun, ref, pair}], [{:atom, nil}], [{:list, tree_set([@struct_1])}]]

      round_1 =
        tree_set([
          {:atom, nil},
          {:tuple, [tree_set([@struct_1]), tree_set([{:atom, nil}])]}
        ])

      round_2 = :ordsets.add_element({:tuple, [tree_set([@struct_1]), round_1]}, round_1)

      assert call_model({:lists, :foldl, 3}, args) == round_2
    end

    test "Hologram function that returns the server as it was" do
      args = [[{:struct, Server, %{}}], [:prim]]

      assert call_model({Server, :put_status, 2}, args) == tree_set([{:struct, Server, %{}}])
    end

    test "a Hologram function that puts a value in the session has no model" do
      assert summary({Server, :put_session, 3}) == nil
    end
  end
end
