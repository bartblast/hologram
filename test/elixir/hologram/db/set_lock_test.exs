defmodule Hologram.DB.SetLockTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.SetLock

  alias Hologram.DB.Connection
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29

  @links MapSet.new([
           {:edge, Module28, :labels, :source, Module28},
           {:edge, Module28, :labels, :target, Module29},
           {:reference, Module28, :channel_id, Module26}
         ])

  # The advisory locks the calling session holds, by mode, under the keys they are named by -
  # PostgreSQL shows a two-key lock's keys as unsigned.
  defp advisory_locks do
    statement =
      "SELECT classid, objid, mode FROM pg_locks " <>
        "WHERE locktype = 'advisory' AND objsubid = 2 AND pid = pg_backend_pid()"

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [])

    rows
    |> Enum.map(fn [classid, objid, mode] -> {mode, {signed(classid), signed(objid)}} end)
    |> Enum.sort()
  end

  defp signed(key) when key >= 2_147_483_648, do: key - 4_294_967_296

  defp signed(key), do: key

  describe "edge_owners/5" do
    test "names the row a pair's source or target id names, by the side the set is read from" do
      assert edge_owners(@links, Module28, "m1", :labels, "l1") == [
               {Module28, "m1"},
               {Module29, "l1"}
             ]
    end

    test "names nothing for a relationship no locked set is stored in" do
      assert edge_owners(@links, Module28, "m1", :other, "l1") == []
    end
  end

  describe "enter!/2" do
    test "takes the shared lock of every owner row" do
      channel_id = Entity.generate_id()
      label_id = Entity.generate_id()

      assert enter!([{Module26, channel_id}, {Module29, label_id}], []) == :ok

      assert advisory_locks() ==
               Enum.sort([
                 {"ShareLock", keys(Module26, channel_id)},
                 {"ShareLock", keys(Module29, label_id)}
               ])
    end

    # Row locks show in pg_locks only as the RowShareLock a locking read holds on the relation.
    test "takes a locking read of every referenced row" do
      owner = {Module26, Entity.generate_id()}

      assert enter!([owner], [owner, {Module29, Entity.generate_id()}]) == :ok
      assert "RowShareLock" in relation_lock_modes(Module26)
      assert "RowShareLock" in relation_lock_modes(Module29)
    end

    test "takes nothing without an owner row" do
      assert enter!([], [{Module29, Entity.generate_id()}]) == :ok
      assert advisory_locks() == []
      refute "RowShareLock" in relation_lock_modes(Module29)
    end
  end

  describe "hold!/2" do
    test "takes the exclusive lock of the owner row" do
      channel_id = Entity.generate_id()

      assert hold!(Module26, channel_id) == :ok
      assert advisory_locks() == [{"ExclusiveLock", keys(Module26, channel_id)}]
    end
  end

  describe "keys/2" do
    test "names two rows of one type apart, and a row apart from one of another type" do
      {type_key, first_key} = keys(Module26, "c1")

      assert {^type_key, second_key} = keys(Module26, "c2")
      assert second_key != first_key
      assert elem(keys(Module29, "c1"), 0) != type_key
    end
  end

  describe "row_owners/3" do
    test "names the row a reference field among the values names" do
      assert row_owners(@links, Module28, %{body: "hi", channel_id: "c1"}) == [{Module26, "c1"}]
    end

    test "names nothing for a reference field holding nil or left out" do
      assert row_owners(@links, Module28, %{channel_id: nil}) == []
      assert row_owners(@links, Module28, %{body: "hi"}) == []
    end

    test "names nothing for a type no locked set holds" do
      assert row_owners(@links, Module29, %{channel_id: "c1"}) == []
    end
  end
end
