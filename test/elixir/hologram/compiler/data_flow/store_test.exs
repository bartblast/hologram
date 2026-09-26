defmodule Hologram.Compiler.DataFlow.StoreTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.Store

  # The tables are linked to the test process and stop with it.
  setup do
    [store: start()]
  end

  describe "fetch/2" do
    test "gives the content back", %{store: store} do
      id = intern(store, [:prim, {:atom, :a}])

      assert fetch(store, id) == [:prim, {:atom, :a}]
    end
  end

  describe "intern/2" do
    test "equal contents get one id", %{store: store} do
      assert intern(store, [:prim]) == intern(store, [:prim])
    end

    test "different contents get different ids", %{store: store} do
      refute intern(store, [:prim]) == intern(store, [{:atom, :a}])
    end

    test "a content with nested ids", %{store: store} do
      inner = intern(store, [{:param, 0}])
      id = intern(store, [{:tuple, [inner, inner]}])

      assert fetch(store, id) == [{:tuple, [inner, inner]}]
    end

    test "the same content interned by many processes at once gets one id", %{store: store} do
      ids =
        1..20
        |> Enum.map(fn _index -> Task.async(fn -> intern(store, [{:atom, :shared}]) end) end)
        |> Task.await_many()

      assert length(Enum.uniq(ids)) == 1
      assert fetch(store, hd(ids)) == [{:atom, :shared}]
    end
  end

  describe "start/1" do
    test "the empty set is id 1", %{store: store} do
      assert intern(store, []) == 1
      assert fetch(store, 1) == []
    end
  end

  describe "stop/1" do
    test "stops the tables" do
      store = start()
      stop(store)

      refute Process.alive?(store.sets.pid)
      refute Process.alive?(store.ids.pid)
      refute Process.alive?(store.memo.pid)
    end
  end
end
