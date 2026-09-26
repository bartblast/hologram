defmodule Hologram.Compiler.DataFlow.ShapeSetTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.ShapeSet

  describe "all?/2" do
    test "every element passes" do
      assert all?(new([{:atom, :a}, {:atom, :b}]), &match?({:atom, _atom}, &1))
    end

    test "an element fails" do
      refute all?(new([{:atom, :a}, :prim]), &match?({:atom, _atom}, &1))
    end

    test "empty set" do
      assert all?(new(), &match?({:atom, _atom}, &1))
    end
  end

  describe "any?/2" do
    test "an element passes" do
      assert any?(new([{:atom, :a}, :prim]), &(&1 == :prim))
    end

    test "no element passes" do
      refute any?(new([{:atom, :a}]), &(&1 == :prim))
    end

    test "empty set" do
      refute any?(new(), &(&1 == :prim))
    end
  end

  describe "empty?/1" do
    test "empty set" do
      assert empty?(new())
    end

    test "set with an element" do
      refute empty?(new([:prim]))
    end
  end

  describe "filter/2" do
    test "keeps the elements that pass" do
      assert filter(new([{:atom, :a}, :prim, {:param, 0}]), &match?({:atom, _atom}, &1)) ==
               new([{:atom, :a}])
    end
  end

  describe "flat_map/2" do
    test "unions the sets the function gives" do
      set = new([{:param, 0}, {:param, 1}])

      assert flat_map(set, fn {:param, index} -> new([{:param, index + 1}, :prim]) end) ==
               new([{:param, 1}, {:param, 2}, :prim])
    end

    test "empty set" do
      assert flat_map(new(), fn shape -> new([shape]) end) == new()
    end
  end

  describe "map/2" do
    test "the set of what the function gives" do
      assert map(new([{:param, 0}, {:param, 1}]), fn _shape -> :prim end) == new([:prim])
    end
  end

  describe "member?/2" do
    test "element of the set" do
      assert member?(new([:prim, {:atom, :a}]), {:atom, :a})
    end

    test "not an element of the set" do
      refute member?(new([:prim]), {:atom, :a})
    end
  end

  describe "new/0" do
    test "empty set" do
      assert size(new()) == 0
    end
  end

  describe "new/1" do
    test "drops duplicates" do
      assert size(new([:prim, {:atom, :a}, :prim])) == 2
    end
  end

  describe "put/2" do
    test "new element" do
      assert put(new([:prim]), {:atom, :a}) == new([:prim, {:atom, :a}])
    end

    test "element already in the set" do
      assert put(new([:prim]), :prim) == new([:prim])
    end
  end

  describe "reduce/3" do
    test "folds the elements" do
      assert reduce(new([{:param, 0}, {:param, 2}]), 0, fn {:param, index}, acc ->
               acc + index
             end) == 2
    end
  end

  describe "size/1" do
    test "number of elements" do
      assert size(new([:prim, {:atom, :a}])) == 2
    end
  end

  describe "to_list/1" do
    test "elements in term order" do
      assert to_list(new([{:param, 0}, :prim, {:atom, :a}])) == [:prim, {:atom, :a}, {:param, 0}]
    end
  end

  describe "union/2" do
    test "elements of both sets, once each" do
      assert union(new([:prim, {:atom, :a}]), new([{:atom, :a}, {:param, 0}])) ==
               new([:prim, {:atom, :a}, {:param, 0}])
    end
  end

  describe "union_all/1" do
    test "elements of every set" do
      assert union_all([new([:prim]), new([{:atom, :a}]), new([:prim])]) ==
               new([:prim, {:atom, :a}])
    end

    test "no sets" do
      assert union_all([]) == new()
    end
  end
end
