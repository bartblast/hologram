defmodule Hologram.Compiler.DataFlow.Rules.TreesTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.Rules.Trees

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct7

  describe "cached/3" do
    test "gives the function's result, remembered in the rule cache" do
      flow = DataFlow.start(PLT.start(), PLT.start())

      assert cached({:key, 1}, flow, fn -> [:prim] end) == [:prim]
      assert cached({:key, 1}, flow, fn -> raise "not called again" end) == [:prim]
      assert PLT.get(flow.rule_cache, {:key, 1}) == {:ok, [:prim]}
    end
  end

  describe "struct_tree/2" do
    test "the given fields' trees, every other field a primitive" do
      assert struct_tree(Struct7, %{note: [{:atom, :a}]}) ==
               [{:struct, Struct7, %{name: [:prim], note: [{:atom, :a}]}}]
    end

    test "a field the struct does not have is left out" do
      assert struct_tree(Struct7, %{other: [{:atom, :a}]}) ==
               [{:struct, Struct7, %{name: [:prim], note: [:prim]}}]
    end

    test "a module that is no struct has the given fields and a rest of primitives" do
      assert struct_tree(NotLoadedModule, %{note: [{:atom, :a}]}) ==
               [{:struct, NotLoadedModule, %{:note => [{:atom, :a}], {:rest} => [:prim]}}]
    end
  end

  describe "tree_leaves/1" do
    test "a struct with no fields, and what its fields hold" do
      tree = [{:struct, Struct7, %{name: [:prim], note: [{:atom, :a}]}}]

      leaves = tree_leaves(tree)

      assert Enum.sort(leaves) == [:prim, {:atom, :a}, {:struct, Struct7, %{}}]
    end

    test "what maps, tuples, lists and bags hold, at any depth" do
      tree = [
        {:map, %{a: [{:param, 0}]}},
        {:tuple, [[{:atom, :ok}], [{:list, [{:bag, [{:param, 1}]}]}]]}
      ]

      leaves = tree_leaves(tree)

      assert Enum.sort(leaves) == [{:atom, :ok}, {:param, 0}, {:param, 1}]
    end

    test "any other shape is itself" do
      call = {:dyn, [{:param, 0}], :load, 1, [[:prim]]}

      assert tree_leaves([call]) == [call]
    end
  end

  describe "union/1" do
    test "the trees' shapes, sorted, each once" do
      assert union([[{:param, 0}, :prim], [:prim, {:atom, :a}]]) == [
               :prim,
               {:atom, :a},
               {:param, 0}
             ]
    end

    test "no trees" do
      assert union([]) == []
    end
  end
end
