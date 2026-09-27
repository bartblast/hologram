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
    test "the set a tree stands for, its nested trees interned", %{store: store} do
      set = from_tree([:prim, {:tuple, [[{:atom, :a}]]}], store)

      assert to_list(set, store) == [:prim, {:tuple, [new([{:atom, :a}], store)]}]
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
    test "alternatives of different kinds stay apart", %{store: store} do
      a = new([:prim], store)

      assert size(new([{:list, a}, {:bag, a}, {:param, 0}], store), store) == 3
    end

    test "bags, parts, contents and maps not known yet merge per kind", %{store: store} do
      a = new([:prim], store)
      b = new([{:atom, :x}], store)
      both = new([:prim, {:atom, :x}], store)

      for kind <- [:as_map, :bag, :contents, :part] do
        assert to_list(new([{kind, a}, {kind, b}], store), store) == [{kind, both}]
      end
    end

    test "drops duplicates", %{store: store} do
      assert size(new([:prim, {:atom, :a}, :prim], store), store) == 2
    end

    test "a set's elements are sorted, each once", %{store: store} do
      assert to_list(new([{:param, 0}, :prim, :prim], store), store) == [:prim, {:param, 0}]
    end

    test "equal sets are one id", %{store: store} do
      assert new([:prim, {:atom, :a}], store) == new([{:atom, :a}, :prim, :prim], store)
    end

    test "dots of different names stay apart", %{store: store} do
      a = new([{:param, 0}], store)

      assert size(new([{:dot, a, :title}, {:dot, a, :note}], store), store) == 2
    end

    test "functions of different refs stay apart", %{store: store} do
      a = new([:prim], store)

      assert size(new([{:fun, {{M, :f, 0}, 1}, a}, {:fun, {{M, :f, 0}, 2}, a}], store), store) ==
               2
    end

    test "nested sets merge too", %{store: store} do
      a = new([{:list, new([:prim], store)}], store)
      b = new([{:list, new([{:atom, :x}], store)}], store)
      inner = new([{:list, new([:prim, {:atom, :x}], store)}], store)

      assert to_list(new([{:list, a}, {:list, b}], store), store) == [{:list, inner}]
    end

    test "two dots of one name become one", %{store: store} do
      a = new([{:param, 0}], store)
      b = new([{:param, 1}], store)
      both = new([{:param, 0}, {:param, 1}], store)

      assert to_list(new([{:dot, a, :title}, {:dot, b, :title}], store), store) ==
               [{:dot, both, :title}]
    end

    test "two functions of one ref become one", %{store: store} do
      ref = {{M, :f, 0}, 1}
      a = new([:prim], store)
      b = new([{:atom, :x}], store)
      both = new([:prim, {:atom, :x}], store)

      assert to_list(new([{:fun, ref, a}, {:fun, ref, b}], store), store) == [{:fun, ref, both}]
    end

    test "two lists become a list of both", %{store: store} do
      a = new([:prim], store)
      b = new([{:atom, :x}], store)
      both = new([:prim, {:atom, :x}], store)

      assert to_list(new([{:list, a}, {:list, b}], store), store) == [{:list, both}]
    end
  end

  describe "put/3" do
    test "an alternative of a kind in the set merges into it", %{store: store} do
      set = new([{:list, new([:prim], store)}], store)
      both = new([:prim, {:atom, :x}], store)

      assert to_list(put(set, {:list, new([{:atom, :x}], store)}, store), store) == [
               {:list, both}
             ]
    end

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
    test "alternatives of a kind merge", %{store: store} do
      set_1 = new([{:list, new([:prim], store)}], store)
      set_2 = new([{:list, new([{:atom, :x}], store)}], store)
      both = new([:prim, {:atom, :x}], store)

      assert to_list(union(set_1, set_2, store), store) == [{:list, both}]
    end

    test "elements of both sets, once each", %{store: store} do
      assert union(
               new([:prim, {:atom, :a}], store),
               new([{:atom, :a}, {:param, 0}], store),
               store
             ) ==
               new([:prim, {:atom, :a}, {:param, 0}], store)
    end

    test "a union of a set with itself is the set", %{store: store} do
      set = new([:prim], store)

      assert union(set, set, store) == set
    end

    test "is remembered per pair of sets", %{store: store} do
      set_1 = new([:prim], store)
      set_2 = new([{:atom, :x}], store)
      union(set_1, set_2, store)
      union(set_2, set_1, store)

      assert Store.memo_count(store, :union) == 1
    end
  end

  describe "union_all/2" do
    test "alternatives of a kind merge", %{store: store} do
      sets = [
        new([{:bag, new([:prim], store)}], store),
        new([{:bag, new([{:atom, :x}], store)}], store)
      ]

      both = new([:prim, {:atom, :x}], store)

      assert to_list(union_all(sets, store), store) == [{:bag, both}]
    end

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
