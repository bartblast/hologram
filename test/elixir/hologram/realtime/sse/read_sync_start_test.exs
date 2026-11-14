defmodule Hologram.Realtime.SSE.ReadSyncStartTest do
  # async: false - a hold on the data model is one persistent term for the whole node.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Realtime.SSE

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.Policy.Edges
  alias Hologram.Sync.Cursor

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @policy_hash "0123456789abcdef0123456789abcdef"

  # The rules this build enforces, stood in the cache so a test can name them: hashing the suite's
  # whole model reads derived field definitions no test of the sync start puts.
  setup do
    on_exit(&Policy.reset_model_facts_cache/0)

    :persistent_term.put({Policy, :hash}, @policy_hash)

    :ok
  end

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

    # Nothing else is read for a first arrival with current rules, so the check that the rules
    # stayed the ones the handshake compared is what meets the hold.
    test "waits for the compile when a hold began before a first arrival's start" do
      on_exit(&Model.release/0)

      Model.hold()

      assert read_sync_start(nil, nil, @policy_hash, false, true) == :held
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

    # A compile held and released between the handshake and these reads leaves them read under
    # rules other than the ones the handshake compared the client's with.
    test "starts over when the rules changed after the handshake" do
      assert read_sync_start(nil, nil, "fedcba9876543210fedcba9876543210", false, true) ==
               :rules_changed
    end

    test "reads nothing for a client arriving for the first time with current rules" do
      assert read_sync_start(nil, nil, @policy_hash, false, true) ==
               {:ok, %{cursor: nil, edges: nil, gap_end: nil, resync_reason: nil, rules: nil}}
    end

    # The session reads the gap again for itself, so what travels on is where it reads from and how
    # far this read reached - the furthest a catch-up frame may vouch for.
    test "hands on where a returning client resumes from and how far its gap reaches" do
      {tx, seq} = seed(200)
      gap_end = seed(201)

      cursor = Cursor.encode(tx, seq, @policy_hash)

      assert read_sync_start(cursor, nil, @policy_hash, false, true) ==
               {:ok,
                %{
                  cursor: cursor,
                  edges: Edges.index(),
                  gap_end: gap_end,
                  resync_reason: nil,
                  rules: nil
                }}
    end

    test "hands on no gap end for a returning client that missed nothing" do
      {tx, seq} = seed(200)

      cursor = Cursor.encode(tx, seq, @policy_hash)

      assert read_sync_start(cursor, nil, @policy_hash, false, true) ==
               {:ok,
                %{
                  cursor: cursor,
                  edges: Edges.index(),
                  gap_end: nil,
                  resync_reason: nil,
                  rules: nil
                }}
    end

    # A client that has to be sent everything again resumes from nowhere - a cursor handed on would
    # have the session replay a gap for a client being told to drop its store.
    test "hands on no place to resume from for a client sent everything again" do
      {tx, seq} = seed(200)

      cursor = Cursor.encode(tx, seq, "fedcba9876543210fedcba9876543210")

      assert read_sync_start(cursor, nil, @policy_hash, false, true) ==
               {:ok,
                %{cursor: nil, edges: nil, gap_end: nil, resync_reason: :policy_hash, rules: nil}}
    end
  end
end
