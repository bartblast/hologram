defmodule Hologram.Sync.CatchupTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Catchup

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity.Model
  alias Hologram.Sync.Cursor
  alias Hologram.Test.Fixtures.Entity.Module2

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  defp effect(entity_type, entity_id) do
    %{entity_id: entity_id, op: :patch_entity, type: entity_type}
  end

  defp places do
    statement = ~s|SELECT "tx", "seq" FROM "hologram_system"."outbox" ORDER BY "tx", "seq"|

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [tx, seq] -> {tx, seq} end)
  end

  defp seed(tx, model_hash \\ Model.hash()) do
    statement = """
    INSERT INTO "hologram_system"."outbox" ("op", "type", "entity_id", "tx", "model_hash")
    VALUES ('del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, $3)
    """

    params = [Codec.encode(@entity_id, :uuid), tx, model_hash]

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end

  describe "deltas/2" do
    test "hands over a row the gap touched as it now stands" do
      row = %Module2{a: true, c: "as it now stands", id: @entity_id}

      assert deltas([effect(Module2, @entity_id)], %{@entity_id => row}) == [
               %{
                 data: row,
                 id: @entity_id,
                 op: :put_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "tells the client to drop a row the gap touched that it may no longer see" do
      assert deltas([effect(Module2, @entity_id)], %{}) == [
               %{
                 id: @entity_id,
                 op: :unsync_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "says one thing about a row the gap touched many times" do
      row = %Module2{a: true, c: "moved three times", id: @entity_id}
      effects = [effect(Module2, @entity_id), effect(Module2, @entity_id)]

      assert [%{data: ^row, op: :put_entity}] = deltas(effects, %{@entity_id => row})
    end

    test "says nothing about a type this build has never compiled" do
      assert deltas([effect("MyApp.TypeOnlyThisTestNames", @entity_id)], %{}) == []
    end

    test "says nothing about a gap that touched nothing" do
      assert deltas([], %{}) == []
    end
  end

  describe "gap/1" do
    test "returns the effects written since the client was last told" do
      seed(200)
      seed(201)

      [{tx, seq}, _second] = places()

      assert {:ok, [effect]} = gap(Cursor.encode(tx, seq))
      assert effect.tx == 201
    end

    test "returns nothing to replay for a client that missed nothing" do
      seed(200)

      [{tx, seq}] = places()

      assert gap(Cursor.encode(tx, seq)) == {:ok, []}
    end

    test "sends everything again to a client whose place cannot be read" do
      seed(200)

      assert gap("not a cursor") == {:full_resync, :cursor}
    end

    test "sends everything again to a client that named no place at all" do
      seed(200)

      assert gap(nil) == {:full_resync, :cursor}
    end

    test "sends everything again when the log was pruned past the client" do
      seed(200)

      [{tx, _seq}] = places()

      assert gap(Cursor.encode(tx - 1, 0)) == {:full_resync, :retention}
    end

    test "sends everything again when the log holds nothing to answer with" do
      assert gap(Cursor.encode(200, 1)) == {:full_resync, :retention}
    end

    test "sends everything again when the gap spans a change of model" do
      seed(200)
      seed(201)
      seed(202, "written under another model")

      [{tx, seq}, _second, _third] = places()

      # The gap is refused WHOLE, not up to the deploy: a replay stopping short would leave the
      # client holding rows of one model and a place that says it holds rows of both.
      assert gap(Cursor.encode(tx, seq)) == {:full_resync, :model_hash}
    end

    test "replays a gap whose effects were all written under the current model" do
      seed(199, "written under another model")
      seed(200)
      seed(201)

      [_pruned, {tx, seq}, _second] = places()

      # The effect from before the client's place is of another model and is none of its business:
      # what it was away for is what comes after.
      assert {:ok, [effect]} = gap(Cursor.encode(tx, seq))
      assert effect.tx == 201
    end
  end
end
