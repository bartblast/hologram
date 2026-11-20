defmodule Hologram.Realtime.SSE.ReadSyncStartTest do
  # async: false - a hold on the data model is one persistent term for the whole node.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Realtime.SSE
  import Hologram.Test.Stubs

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.Sync.Cursor
  alias Hologram.Test.Fixtures.Entity.Module2

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @policy_hash "0123456789abcdef0123456789abcdef"
  @synced_types [Module2]

  use_module_stub :query_cache

  # The rules this build enforces, stood in the cache so a test can name them: hashing the suite's
  # whole model reads derived field definitions no test of the sync start puts.
  setup do
    on_exit(&Policy.reset_model_facts_cache/0)

    :persistent_term.put({Policy, :hash}, @policy_hash)

    setup_query_cache(QueryCacheStub, false)

    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
      permission_checking?: false,
      synced_types: @synced_types
    })

    :ok
  end

  # The hash a place filled by this build names its types by.
  defp types_hash, do: Cursor.types_hash(@synced_types, false, Model.hash())

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
  # The session reads the gap again for itself, and that read has to answer at the same doors the
  # start read did, under the same rules and types.
  describe "sync_session_opts/5" do
    defp gap_reader(cursor) do
      start = %{cursor: cursor, rules: nil, types_hash: types_hash()}
      connection = %{applied_seq: nil, fill_place: {200, 0}, replica_id: nil}

      sync_session_opts(nil, MyApp.Page, @policy_hash, start, connection)[:read_gap]
    end

    test "hands the session a gap reader that reads past a place filled under the same rules and types" do
      {tx, seq} = seed(200)

      assert {:ok, [], _edge} = gap_reader(Cursor.encode(tx, seq, @policy_hash, types_hash())).()
    end

    test "hands the session a gap reader that refuses a place filled with other types" do
      {tx, seq} = seed(200)

      cursor = Cursor.encode(tx, seq, @policy_hash, Cursor.types_hash([], false, Model.hash()))

      assert gap_reader(cursor).() == {:full_resync, :synced_types}
    end

    test "hands the session a gap reader that refuses a place filled under another model" do
      {tx, seq} = seed(200)

      cursor =
        Cursor.encode(tx, seq, @policy_hash, Cursor.types_hash(@synced_types, false, "0ld"))

      assert gap_reader(cursor).() == {:full_resync, :synced_types}
    end

    test "hands the session a gap reader that refuses a place judged under other rules" do
      {tx, seq} = seed(200)

      cursor = Cursor.encode(tx, seq, "fedcba9876543210fedcba9876543210", types_hash())

      assert gap_reader(cursor).() == {:full_resync, :policy_hash}
    end
  end

  describe "read_sync_start/5" do
    test "waits for the compile when a hold began before the rules a stale client is handed" do
      on_exit(&Model.release/0)

      Model.hold()

      assert read_sync_start("1.2.0123.4567", nil, @policy_hash, true, true) == :held
    end

    # Every start names the model its rows are read under in the types hash, which is what meets the
    # hold.
    test "waits for the compile when a hold began before a first arrival's start" do
      on_exit(&Model.release/0)

      Model.hold()

      assert read_sync_start(nil, nil, @policy_hash, false, true) == :held
    end

    # A place the log still reaches, and an effect after it the client missed: the hold meets the
    # model hash the place is compared against before the gap is.
    test "waits for the compile when a hold began before a returning client's catch-up" do
      on_exit(&Model.release/0)

      {tx, seq} = seed(200)
      seed(201)

      # Named before the hold, which refuses the model hash a place names.
      cursor = Cursor.encode(tx, seq, @policy_hash, types_hash())

      Model.hold()

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
               {:ok,
                %{
                  cursor: nil,
                  lens: nil,
                  resync_reason: nil,
                  rules: nil,
                  synced_types: nil,
                  types_hash: types_hash()
                }}
    end

    # The session reads the gap for itself, so what travels on is where it reads from.
    test "hands on where a returning client resumes from" do
      {tx, seq} = seed(200)
      seed(201)

      cursor = Cursor.encode(tx, seq, @policy_hash, types_hash())

      assert read_sync_start(cursor, nil, @policy_hash, false, true) ==
               {:ok,
                %{
                  cursor: cursor,
                  lens: nil,
                  resync_reason: nil,
                  rules: nil,
                  synced_types: nil,
                  types_hash: types_hash()
                }}
    end

    # A client that has to be sent everything again resumes from nowhere - a cursor handed on would
    # have the session replay a gap for a client being told to drop its store.
    test "hands on no place to resume from for a client sent everything again" do
      {tx, seq} = seed(200)

      cursor = Cursor.encode(tx, seq, "fedcba9876543210fedcba9876543210", types_hash())

      assert read_sync_start(cursor, nil, @policy_hash, false, true) ==
               {:ok,
                %{
                  cursor: nil,
                  lens: nil,
                  resync_reason: :policy_hash,
                  rules: nil,
                  synced_types: nil,
                  types_hash: types_hash()
                }}
    end

    # A migration can change rows at rest with nothing in the log to say so, and a tab built against
    # an older model keeps the rows it holds across the deploy.
    test "sends everything again to a client filled under another model" do
      {tx, seq} = seed(200)

      cursor =
        Cursor.encode(tx, seq, @policy_hash, Cursor.types_hash(@synced_types, false, "0ld"))

      assert read_sync_start(cursor, nil, @policy_hash, false, true) ==
               {:ok,
                %{
                  cursor: nil,
                  lens: nil,
                  resync_reason: :synced_types,
                  rules: nil,
                  synced_types: nil,
                  types_hash: types_hash()
                }}
    end

    # A client of another model is sent only the types its bundle names, and its place names those.
    test "names the types an old client is served in the place it is handed" do
      serving = %{lens: :a_lens, types: [Module2]}

      assert {:ok, start} = read_sync_start(nil, nil, @policy_hash, false, true, serving)

      assert start.lens == :a_lens
      assert start.synced_types == [Module2]
      assert start.types_hash == Cursor.types_hash([Module2], false, Model.hash())
    end

    test "names the types an old client is served, not the build's, in the place it resumes from" do
      {tx, seq} = seed(200)

      # Filled with the build's own types, which the old client isn't served.
      cursor =
        Cursor.encode(
          tx,
          seq,
          @policy_hash,
          Cursor.types_hash([Module2, MyApp.Other], false, Model.hash())
        )

      serving = %{lens: :a_lens, types: [Module2]}

      assert {:ok, %{cursor: nil, resync_reason: :synced_types}} =
               read_sync_start(cursor, nil, @policy_hash, false, true, serving)
    end

    # A deploy that starts syncing a type moves no row of it, so only the place's own record of the
    # types says the client was filled without it.
    test "sends everything again to a client filled with other types" do
      {tx, seq} = seed(200)

      cursor = Cursor.encode(tx, seq, @policy_hash, Cursor.types_hash([], false, Model.hash()))

      assert read_sync_start(cursor, nil, @policy_hash, false, true) ==
               {:ok,
                %{
                  cursor: nil,
                  lens: nil,
                  resync_reason: :synced_types,
                  rules: nil,
                  synced_types: nil,
                  types_hash: types_hash()
                }}
    end
  end
end
