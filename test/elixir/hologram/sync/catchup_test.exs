defmodule Hologram.Sync.CatchupTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Catchup

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Oplog
  alias Hologram.Entity.Model
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @policy_hash "0123456789abcdef0123456789abcdef"
  @types_hash "00112233445566778899aabbccddeeff"

  defp places do
    statement = ~s|SELECT "tx", "seq" FROM "hologram_system"."oplog" ORDER BY "tx", "seq"|

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [tx, seq] -> {tx, seq} end)
  end

  # One statement rather than thousands of round trips: the oversized-gap case needs more effects
  # than the cap allows, and seeding those one at a time would dominate the suite.
  defp seed_many(count) do
    statement = """
    INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "tx", "model_hash")
    SELECT 'del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, (200 + i)::text::xid8, $2
    FROM generate_series(1, $3) AS i
    """

    params = [Codec.encode(@entity_id, :uuid), Model.hash(), count]

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end

  defp seed(tx, model_hash \\ Model.hash()) do
    statement = """
    INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "tx", "model_hash")
    VALUES ('del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, $3)
    """

    params = [Codec.encode(@entity_id, :uuid), tx, model_hash]

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end

  describe "check/3" do
    test "lets a client that missed what fits in a replay resume" do
      seed(200)
      seed(201)

      [{tx, seq}, _second] = places()

      assert check(Cursor.encode(tx, seq, @policy_hash, @types_hash), @policy_hash, @types_hash) ==
               :ok
    end

    test "sends everything again to a client whose place cannot be read" do
      assert check("not a cursor", @policy_hash, @types_hash) == {:full_resync, :cursor}
    end

    test "sends everything again to a client judged under other rules" do
      seed(200)

      [{tx, seq}] = places()
      cursor = Cursor.encode(tx, seq, "fedcba9876543210fedcba9876543210", @types_hash)

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :policy_hash}
    end

    test "sends everything again to a client filled with other types" do
      seed(200)

      [{tx, seq}] = places()
      cursor = Cursor.encode(tx, seq, @policy_hash, "ffeeddccbbaa99887766554433221100")

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :synced_types}
    end

    test "sends everything again when the client's place predates the log" do
      seed(200)

      cursor = Cursor.encode(100, 0, @policy_hash, @types_hash)

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :retention}
    end

    test "sends everything again when the gap is too big to be worth replaying" do
      seed_many(Catchup.gap_limit() + 2)

      [{tx, seq} | _rest] = places()
      cursor = Cursor.encode(tx, seq, @policy_hash, @types_hash)

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :gap_too_large}
    end

    test "sends everything again when the gap spans a change of model" do
      seed(200)
      seed(201, "written under another model")

      [{tx, seq}, _second] = places()
      cursor = Cursor.encode(tx, seq, @policy_hash, @types_hash)

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :model_hash}
    end
  end

  describe "gap/4" do
    test "returns the effects written since the client was last told" do
      seed(200)
      seed(201)

      [{tx, seq}, _second] = places()

      assert {:ok, [effect], _edge} =
               gap(
                 Cursor.encode(tx, seq, @policy_hash, @types_hash),
                 nil,
                 @policy_hash,
                 @types_hash
               )

      assert effect.tx == 201
    end

    test "returns nothing to replay for a client that missed nothing" do
      seed(200)

      [{tx, seq}] = places()

      assert {:ok, [], _edge} =
               gap(
                 Cursor.encode(tx, seq, @policy_hash, @types_hash),
                 nil,
                 @policy_hash,
                 @types_hash
               )
    end

    # Read before the effects, so it can never be past what the read saw finish.
    test "answers the edge below which every transaction had finished before the read" do
      seed(200)

      [{tx, seq}] = places()

      assert {:ok, [], edge} =
               gap(
                 Cursor.encode(tx, seq, @policy_hash, @types_hash),
                 nil,
                 @policy_hash,
                 @types_hash
               )

      assert is_integer(edge)
      assert edge <= Oplog.current_xmin()
    end

    test "sends everything again to a client whose place cannot be read" do
      seed(200)

      assert gap("not a cursor", nil, @policy_hash, @types_hash) == {:full_resync, :cursor}
    end

    test "sends everything again to a client that named no place at all" do
      seed(200)

      assert gap(nil, nil, @policy_hash, @types_hash) == {:full_resync, :cursor}
    end

    # A place beyond what the log's columns hold used to reach the driver and raise there, on a
    # connection that had already answered 200 - so the client got an opened-then-dead stream and
    # came back with the same forged place. Seeded, because an empty log answers at the coverage
    # door before the read is ever reached.
    test "sends everything again to a client whose place no row could carry" do
      seed(200)

      forged = "99999999999999999999999.0.#{@policy_hash}.#{@types_hash}"

      assert gap(forged, nil, @policy_hash, @types_hash) == {:full_resync, :cursor}
    end

    # A deploy that changes who may read a row moves no row, so only the place's own record of the
    # rules says what the client holds was decided by others - even when nothing moved since.
    test "sends everything again to a client judged under other rules" do
      seed(200)

      [{tx, seq}] = places()

      cursor = Cursor.encode(tx, seq, "fedcba9876543210fedcba9876543210", @types_hash)

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :policy_hash}
    end

    # A deploy that starts syncing a type moves no row of it either, so only the place's own record
    # of the types says the client holds none of it.
    test "sends everything again to a client filled with other types" do
      seed(200)

      [{tx, seq}] = places()

      cursor = Cursor.encode(tx, seq, @policy_hash, "ffeeddccbbaa99887766554433221100")

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :synced_types}
    end

    # The rules are asked about first, so a client judged under other rules and filled with other
    # types is told the rules changed.
    test "sends everything again under other rules before asking about the types" do
      seed(200)

      [{tx, seq}] = places()

      cursor =
        Cursor.encode(
          tx,
          seq,
          "fedcba9876543210fedcba9876543210",
          "ffeeddccbbaa99887766554433221100"
        )

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :policy_hash}
    end

    # Asked before the log is, so a client judged under other rules is not first told its place is
    # out of reach - both send everything again, but only one says why.
    test "sends everything again under other rules even when the place predates the log" do
      seed(200)

      [{tx, _seq}] = places()

      cursor = Cursor.encode(tx - 1, 0, "fedcba9876543210fedcba9876543210", @types_hash)

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :policy_hash}
    end

    test "sends everything again when the client's place predates the log" do
      seed(200)

      [{tx, _seq}] = places()

      assert gap(
               Cursor.encode(tx - 1, 0, @policy_hash, @types_hash),
               nil,
               @policy_hash,
               @types_hash
             ) ==
               {:full_resync, :retention}
    end

    test "sends everything again when the log holds nothing to answer with" do
      assert gap(Cursor.encode(200, 1, @policy_hash, @types_hash), nil, @policy_hash, @types_hash) ==
               {:full_resync, :retention}
    end

    # The door that keeps a returning client from killing its own connection: the gap is read on the
    # connection process, which is killed at a million words, and a typical effect measures 69 of
    # them. Without a cap a client back from a long absence would breach it, be disconnected, and
    # reconnect with the same cursor to do it again - a loop it never escapes. The cap is 5,000, and
    # this seeds past it rather than restating the number.
    test "sends everything again when the gap is too big to be worth replaying" do
      # One past the cap AFTER the cursor, which consumes the first row seeded.
      seed_many(Catchup.gap_limit() + 2)

      [{tx, seq} | _rest] = places()

      assert gap(
               Cursor.encode(tx, seq, @policy_hash, @types_hash),
               nil,
               @policy_hash,
               @types_hash
             ) ==
               {:full_resync, :gap_too_large}
    end

    test "replays a gap that fits" do
      seed_many(3)

      [{tx, seq} | _rest] = places()

      assert {:ok, effects, _edge} =
               gap(
                 Cursor.encode(tx, seq, @policy_hash, @types_hash),
                 nil,
                 @policy_hash,
                 @types_hash
               )

      assert length(effects) == 2
    end

    test "sends everything again when the gap spans a change of model" do
      seed(200)
      seed(201)
      seed(202, "written under another model")

      [{tx, seq}, _second, _third] = places()

      # The gap is refused WHOLE, not up to the deploy: a replay stopping short would leave the
      # client holding rows of one model and a place that says it holds rows of both.
      assert gap(
               Cursor.encode(tx, seq, @policy_hash, @types_hash),
               nil,
               @policy_hash,
               @types_hash
             ) ==
               {:full_resync, :model_hash}
    end

    test "replays a gap whose effects were all written under the current model" do
      seed(199, "written under another model")
      seed(200)
      seed(201)

      [_pruned, {tx, seq}, _second] = places()

      # The effect from before the client's place is of another model and is none of its business:
      # what it was away for is what comes after.
      assert {:ok, [effect], _edge} =
               gap(
                 Cursor.encode(tx, seq, @policy_hash, @types_hash),
                 nil,
                 @policy_hash,
                 @types_hash
               )

      assert effect.tx == 201
    end
  end
end
