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
  @other_log_id "ffeeddccbbaa99887766554433221100"

  defp cursor(place, policy_hash \\ @policy_hash, types_hash \\ @types_hash) do
    Cursor.encode(place, Oplog.log_id(), policy_hash, types_hash)
  end

  defp places(rows) do
    Enum.map(rows, fn [seq, tx, inserted_at] ->
      Oplog.place(%{inserted_at: inserted_at, seq: seq, tx: tx})
    end)
  end

  # One statement rather than thousands of round trips: the oversized-gap case needs more effects
  # than the cap allows, and seeding those one at a time would dominate the suite.
  defp seed_many(count) do
    statement = """
    INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "tx", "model_hash")
    SELECT 'del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, (200 + i)::text::xid8, $2
    FROM generate_series(1, $3) AS i
    RETURNING "seq", "tx", "inserted_at"
    """

    params = [Codec.encode(@entity_id, :uuid), Model.hash(), count]

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, params)

    rows
    |> places()
    |> Enum.sort()
  end

  # What a crash or a promoted standby does to the server's run, which can lose commits the
  # client holds although its entry is still in the log.
  defp crash_server do
    {:ok, _result} =
      Connection.query(~s|UPDATE "hologram_system"."server_run" SET "run" = gen_random_uuid()|)

    :ok
  end

  defp seed(tx, model_hash \\ Model.hash()) do
    statement = """
    INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "tx", "model_hash")
    VALUES ('del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, $3)
    RETURNING "seq", "tx", "inserted_at"
    """

    params = [Codec.encode(@entity_id, :uuid), tx, model_hash]

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, params)

    [place] = places(rows)

    place
  end

  describe "check/3" do
    test "lets a client that missed what fits in a replay resume" do
      place = seed(200)
      seed(201)

      assert check(cursor(place), @policy_hash, @types_hash) == :ok
    end

    test "lets a client placed before the first entry resume" do
      seed(200)

      assert check(cursor({0, 0, 0}), @policy_hash, @types_hash) == :ok
    end

    test "sends everything again to a client whose place cannot be read" do
      assert check("not a cursor", @policy_hash, @types_hash) == {:full_resync, :cursor}
    end

    test "sends everything again to a client judged under other rules" do
      place = seed(200)

      cursor = cursor(place, "fedcba9876543210fedcba9876543210")

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :policy_hash}
    end

    test "sends everything again to a client filled with other types" do
      place = seed(200)

      cursor = cursor(place, @policy_hash, "ffeeddccbbaa99887766554433221100")

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :synced_types}
    end

    # A dropped database claimed again starts its serials over, so the same place names other
    # entries there.
    test "sends everything again to a client placed in another log" do
      place = seed(200)

      cursor = Cursor.encode(place, @other_log_id, @policy_hash, @types_hash)

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :retention}
    end

    test "sends everything again to a client placed before the server crashed" do
      cursor = cursor(seed(200))
      :ok = crash_server()

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :retention}
    end

    test "sends everything again while the server names no run" do
      cursor = cursor(seed(200))

      {:ok, _result} = Connection.query(~s|DELETE FROM "hologram_system"."server_run"|)

      assert check(cursor, @policy_hash, @types_hash) == {:full_resync, :retention}
    end

    test "sends everything again when the log no longer holds the client's entry" do
      {seq, tx, inserted_at} = seed(200)

      assert check(cursor({seq + 1, tx, inserted_at}), @policy_hash, @types_hash) ==
               {:full_resync, :retention}
    end

    # What a server that lost the commit of the client's entry leaves at its seq.
    test "sends everything again when another entry is at the client's seq" do
      {seq, tx, inserted_at} = seed(200)

      assert check(cursor({seq, tx + 1, inserted_at}), @policy_hash, @types_hash) ==
               {:full_resync, :retention}
    end

    test "sends everything again when the gap is too big to be worth replaying" do
      [place | _rest] = seed_many(Catchup.gap_limit() + 2)

      assert check(cursor(place), @policy_hash, @types_hash) == {:full_resync, :gap_too_large}
    end

    test "sends everything again when the gap spans a change of model" do
      place = seed(200)
      seed(201, "written under another model")

      assert check(cursor(place), @policy_hash, @types_hash) == {:full_resync, :model_hash}
    end
  end

  describe "gap/4" do
    test "returns the effects written since the client was last told" do
      place = seed(200)
      seed(201)

      assert {:ok, [effect]} = gap(cursor(place), nil, @policy_hash, @types_hash)
      assert effect.tx == 201
    end

    test "returns nothing to replay for a client that missed nothing" do
      place = seed(200)

      assert gap(cursor(place), nil, @policy_hash, @types_hash) == {:ok, []}
    end

    # Serials go out as saves write, so a later transaction's entry can sit below an earlier one's.
    test "returns the effects above the client's seq, whatever their transactions" do
      place = seed(201)
      seed(200)

      assert {:ok, [effect]} = gap(cursor(place), nil, @policy_hash, @types_hash)
      assert effect.tx == 200
    end

    test "returns every effect to a client placed before the first entry" do
      seed(200)
      seed(201)

      assert {:ok, [first, second]} = gap(cursor({0, 0, 0}), nil, @policy_hash, @types_hash)
      assert {first.tx, second.tx} == {200, 201}
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
    # came back with the same forged place.
    test "sends everything again to a client whose place no row could carry" do
      seed(200)

      forged = "99999999999999999999999.0.0.#{Oplog.log_id()}.#{@policy_hash}.#{@types_hash}"

      assert gap(forged, nil, @policy_hash, @types_hash) == {:full_resync, :cursor}
    end

    # A deploy that changes who may read a row moves no row, so only the place's own record of the
    # rules says what the client holds was decided by others - even when nothing moved since.
    test "sends everything again to a client judged under other rules" do
      place = seed(200)

      cursor = cursor(place, "fedcba9876543210fedcba9876543210")

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :policy_hash}
    end

    # A deploy that starts syncing a type moves no row of it either, so only the place's own record
    # of the types says the client holds none of it.
    test "sends everything again to a client filled with other types" do
      place = seed(200)

      cursor = cursor(place, @policy_hash, "ffeeddccbbaa99887766554433221100")

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :synced_types}
    end

    # The rules are asked about first, so a client judged under other rules and filled with other
    # types is told the rules changed.
    test "sends everything again under other rules before asking about the types" do
      place = seed(200)

      cursor =
        cursor(place, "fedcba9876543210fedcba9876543210", "ffeeddccbbaa99887766554433221100")

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :policy_hash}
    end

    # Asked before the log is, so a client judged under other rules is not first told its place is
    # out of reach - both send everything again, but only one says why.
    test "sends everything again under other rules even when the log no longer holds the place" do
      {seq, tx, inserted_at} = seed(200)

      cursor = cursor({seq + 1, tx, inserted_at}, "fedcba9876543210fedcba9876543210")

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :policy_hash}
    end

    test "sends everything again to a client placed in another log" do
      place = seed(200)

      cursor = Cursor.encode(place, @other_log_id, @policy_hash, @types_hash)

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :retention}
    end

    test "sends everything again to a client placed before the server crashed" do
      cursor = cursor(seed(200))
      :ok = crash_server()

      assert gap(cursor, nil, @policy_hash, @types_hash) == {:full_resync, :retention}
    end

    test "sends everything again when the log no longer holds the client's entry" do
      {seq, tx, inserted_at} = seed(200)

      assert gap(cursor({seq + 1, tx, inserted_at}), nil, @policy_hash, @types_hash) ==
               {:full_resync, :retention}
    end

    # What a server that lost the commit of the client's entry leaves at its seq: the serials above
    # what it kept went to other saves, so the client's place says nothing of what it holds.
    test "sends everything again when another entry is at the client's seq" do
      {seq, tx, inserted_at} = seed(200)

      assert gap(cursor({seq, tx, inserted_at + 1}), nil, @policy_hash, @types_hash) ==
               {:full_resync, :retention}
    end

    # The door that keeps a returning client from killing its own connection: the gap is read on the
    # connection process, which is killed at a million words, and a typical effect measures 69 of
    # them. Without a cap a client back from a long absence would breach it, be disconnected, and
    # reconnect with the same cursor to do it again - a loop it never escapes. The cap is 5,000, and
    # this seeds past it rather than restating the number.
    test "sends everything again when the gap is too big to be worth replaying" do
      # One past the cap AFTER the cursor, which consumes the first row seeded.
      [place | _rest] = seed_many(Catchup.gap_limit() + 2)

      assert gap(cursor(place), nil, @policy_hash, @types_hash) == {:full_resync, :gap_too_large}
    end

    test "replays a gap that fits" do
      [place | _rest] = seed_many(3)

      assert {:ok, effects} = gap(cursor(place), nil, @policy_hash, @types_hash)
      assert length(effects) == 2
    end

    test "sends everything again when the gap spans a change of model" do
      place = seed(200)
      seed(201)
      seed(202, "written under another model")

      # The gap is refused WHOLE, not up to the deploy: a replay stopping short would leave the
      # client holding rows of one model and a place that says it holds rows of both.
      assert gap(cursor(place), nil, @policy_hash, @types_hash) == {:full_resync, :model_hash}
    end

    test "replays a gap whose effects were all written under the current model" do
      seed(199, "written under another model")
      place = seed(200)
      seed(201)

      # The effect from before the client's place is of another model and is none of its business:
      # what it was away for is what comes after.
      assert {:ok, [effect]} = gap(cursor(place), nil, @policy_hash, @types_hash)
      assert effect.tx == 201
    end
  end
end
