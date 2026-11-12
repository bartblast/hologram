defmodule Hologram.Realtime.SSE.ReadSyncStartTest do
  # async: false - a hold on the data model is one persistent term for the whole node.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Realtime.SSE

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity.Model
  alias Hologram.Sync.Cursor

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @policy_hash "0123456789abcdef0123456789abcdef"

  defp seed(tx) do
    statement = """
    INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "tx", "model_hash")
    VALUES ('del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, $3)
    RETURNING "tx", "seq"
    """

    params = [Codec.encode(@entity_id, :uuid), tx, Model.hash()]

    {:ok, %Postgrex.Result{rows: [[tx, seq]]}} = Connection.query(statement, params)

    {tx, seq}
  end

  # Starting a sync reads the data model after the handshake found it released, and a live reload
  # can hold it in between - the client then waits for the compile like one arriving under the
  # hold, rather than the stream raising.
  describe "read_sync_start/5" do
    test "waits for the compile when a hold began before the rules a stale client is handed" do
      on_exit(&Model.release/0)

      Model.hold()

      assert read_sync_start("1.2.0123", nil, @policy_hash, true, true) == :held
    end

    # A place the log still reaches, and an effect after it the client missed: a gap holding
    # effects is compared against the model, which is the read the hold refuses.
    test "waits for the compile when a hold began before a returning client's catch-up" do
      on_exit(&Model.release/0)

      {tx, seq} = seed(200)
      seed(201)

      Model.hold()

      cursor = Cursor.encode(tx, seq, @policy_hash)

      assert read_sync_start(cursor, nil, @policy_hash, false, true) == :held
    end

    test "reads nothing for a client arriving for the first time with current rules" do
      assert read_sync_start(nil, nil, @policy_hash, false, true) ==
               {:ok, %{edges: nil, gap: nil, grants_then: nil, resync_reason: nil, rules: nil}}
    end
  end
end
