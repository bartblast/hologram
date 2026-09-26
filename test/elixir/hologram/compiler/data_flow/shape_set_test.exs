defmodule Hologram.Compiler.DataFlow.ShapeSetTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.ShapeSet

  alias Hologram.Compiler.DataFlow.Store

  # The store is linked to the test process and stops with it.
  setup do
    [store: Store.start()]
  end

  describe "all?/3" do
    test "every element passes", %{store: store} do
      assert all?(new([{:atom, :a}, {:atom, :b}], store), &match?({:atom, _atom}, &1), store)
    end

    test "an element fails", %{store: store} do
      refute all?(new([{:atom, :a}, :prim], store), &match?({:atom, _atom}, &1), store)
    end

    test "empty set", %{store: store} do
      assert all?(new(store), &match?({:atom, _atom}, &1), store)
    end
  end

  describe "any?/3" do
    test "an element passes", %{store: store} do
      assert any?(new([{:atom, :a}, :prim], store), &(&1 == :prim), store)
    end

    test "no element passes", %{store: store} do
      refute any?(new([{:atom, :a}], store), &(&1 == :prim), store)
    end

    test "empty set", %{store: store} do
      refute any?(new(store), &(&1 == :prim), store)
    end
  end

  describe "empty?/2" do
    test "empty set", %{store: store} do
      assert empty?(new(store), store)
    end

    test "set with an element", %{store: store} do
      refute empty?(new([:prim], store), store)
    end
  end

  describe "filter/3" do
    test "keeps the elements that pass", %{store: store} do
      assert filter(
               new([{:atom, :a}, :prim, {:param, 0}], store),
               &match?({:atom, _atom}, &1),
               store
             ) ==
               new([{:atom, :a}], store)
    end
  end

  describe "flat_map/3" do
    test "unions the sets the function gives", %{store: store} do
      set = new([{:param, 0}, {:param, 1}], store)

      assert flat_map(
               set,
               fn {:param, index} -> new([{:param, index + 1}, :prim], store) end,
               store
             ) ==
               new([{:param, 1}, {:param, 2}, :prim], store)
    end

    test "empty set", %{store: store} do
      assert flat_map(new(store), fn shape -> new([shape], store) end, store) == new(store)
    end
  end

  describe "from_tree/2" do
    test "the set a tree stands for", %{store: store} do
      set = from_tree([:prim, {:tuple, [[{:atom, :a}]]}], store)

      assert to_list(set, store) == [:prim, {:tuple, [[{:atom, :a}]]}]
    end
  end

  describe "map/3" do
    test "the set of what the function gives", %{store: store} do
      assert map(new([{:param, 0}, {:param, 1}], store), fn _shape -> :prim end, store) ==
               new([:prim], store)
    end
  end

  describe "member?/3" do
    test "element of the set", %{store: store} do
      assert member?(new([:prim, {:atom, :a}], store), {:atom, :a}, store)
    end

    test "not an element of the set", %{store: store} do
      refute member?(new([:prim], store), {:atom, :a}, store)
    end
  end

  describe "new/1" do
    test "empty set", %{store: store} do
      assert size(new(store), store) == 0
    end
  end

  describe "new/2" do
    test "drops duplicates", %{store: store} do
      assert size(new([:prim, {:atom, :a}, :prim], store), store) == 2
    end

    test "a set is a sorted list without duplicates", %{store: store} do
      assert new([{:param, 0}, :prim, :prim], store) == [:prim, {:param, 0}]
    end
  end

  describe "put/3" do
    test "new element", %{store: store} do
      assert put(new([:prim], store), {:atom, :a}, store) == new([:prim, {:atom, :a}], store)
    end

    test "element already in the set", %{store: store} do
      assert put(new([:prim], store), :prim, store) == new([:prim], store)
    end
  end

  describe "reduce/4" do
    test "folds the elements", %{store: store} do
      assert reduce(
               new([{:param, 0}, {:param, 2}], store),
               0,
               fn {:param, index}, acc ->
                 acc + index
               end,
               store
             ) == 2
    end
  end

  describe "size/2" do
    test "number of elements", %{store: store} do
      assert size(new([:prim, {:atom, :a}], store), store) == 2
    end
  end

  describe "to_list/2" do
    test "elements in term order", %{store: store} do
      assert to_list(new([{:param, 0}, :prim, {:atom, :a}], store), store) == [
               :prim,
               {:atom, :a},
               {:param, 0}
             ]
    end
  end

  describe "union/3" do
    test "elements of both sets, once each", %{store: store} do
      assert union(
               new([:prim, {:atom, :a}], store),
               new([{:atom, :a}, {:param, 0}], store),
               store
             ) ==
               new([:prim, {:atom, :a}, {:param, 0}], store)
    end
  end

  describe "union_all/2" do
    test "elements of every set", %{store: store} do
      assert union_all(
               [new([:prim], store), new([{:atom, :a}], store), new([:prim], store)],
               store
             ) ==
               new([:prim, {:atom, :a}], store)
    end

    test "no sets", %{store: store} do
      assert union_all([], store) == new(store)
    end
  end
end
