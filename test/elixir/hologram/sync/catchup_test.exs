defmodule Hologram.Sync.CatchupTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Catchup

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity.Model
  alias Hologram.Query
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.WireData
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  defp effect(entity_type, entity_id) do
    %{entity_id: entity_id, op: :patch_entity, type: entity_type}
  end

  defp places do
    statement = ~s|SELECT "tx", "seq" FROM "hologram_system"."outbox" ORDER BY "tx", "seq"|

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [tx, seq] -> {tx, seq} end)
  end

  # One statement rather than thousands of round trips: the oversized-gap case needs more effects
  # than the cap allows, and seeding those one at a time would dominate the suite.
  defp seed_many(count) do
    statement = """
    INSERT INTO "hologram_system"."outbox" ("op", "type", "entity_id", "tx", "model_hash")
    SELECT 'del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, (200 + i)::text::xid8, $2
    FROM generate_series(1, $3) AS i
    """

    params = [Codec.encode(@entity_id, :uuid), Model.hash(), count]

    {:ok, _result} = Connection.query(statement, params)

    :ok
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

  # A grant effect carries the row it names, which is what a revoked grant is rebuilt from.
  defp seed_grant(tx, op, grant) do
    statement = """
    INSERT INTO "hologram_system"."outbox"
      ("op", "type", "entity_id", "data", "tx", "model_hash")
    VALUES ($1, 'Hologram.Auth.RoleGrant', $2, $3::jsonb, $4, $5)
    """

    data = %{
      "id" => grant.id,
      "entity_id" => grant.entity_id,
      "resource_type" => grant.resource_type && Codec.encode_enum_value(grant.resource_type),
      "role" => Codec.encode_enum_value(grant.role),
      "user_id" => grant.user_id
    }

    params = [op, Codec.encode(grant.id, :uuid), data, tx, Model.hash()]

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end

  # The rows this suite seeds are synthetic, at transaction ids far below any real one - so the
  # writes that set a test up (a resource, a grant) would sort AFTER them and land in the gap.
  # Emptying the log once the setup is done leaves the seeds as the whole of it.
  defp clear_log do
    {:ok, _result} = Connection.query(~s|TRUNCATE "hologram_system"."outbox"|)

    :ok
  end

  defp stored_grant(user_id) do
    RoleGrant
    |> Query.filter(user_id: user_id)
    |> Query.normalize()
    |> QueryRunner.run(DB.mapping())
    |> hd()
  end

  defp user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  describe "deltas/2" do
    test "hands over a row the gap touched as it now stands" do
      row = %Module2{a: true, c: "as it now stands", id: @entity_id}

      assert deltas([effect(Module2, @entity_id)], %{@entity_id => row}) == [
               %{
                 data: WireData.row(row),
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

      assert [%{data: data, op: :put_entity}] = deltas(effects, %{@entity_id => row})
      assert data.c == "moved three times"
    end

    test "says nothing about a type this build has never compiled" do
      assert deltas([effect("MyApp.TypeOnlyThisTestNames", @entity_id)], %{}) == []
    end

    test "says nothing about a gap that touched nothing" do
      assert deltas([], %{}) == []
    end
  end

  describe "gap/2" do
    test "returns the effects written since the client was last told" do
      seed(200)
      seed(201)

      [{tx, seq}, _second] = places()

      assert {:ok, [effect], nil} = gap(Cursor.encode(tx, seq), nil)
      assert effect.tx == 201
    end

    test "returns nothing to replay for a client that missed nothing" do
      seed(200)

      [{tx, seq}] = places()

      assert gap(Cursor.encode(tx, seq), nil) == {:ok, [], nil}
    end

    test "sends everything again to a client whose place cannot be read" do
      seed(200)

      assert gap("not a cursor", nil) == {:full_resync, :cursor}
    end

    test "sends everything again to a client that named no place at all" do
      seed(200)

      assert gap(nil, nil) == {:full_resync, :cursor}
    end

    # A place beyond what the log's columns hold used to reach the driver and raise there, on a
    # connection that had already answered 200 - so the client got an opened-then-dead stream and
    # came back with the same forged place. Seeded, because an empty log answers at the coverage
    # door before the read is ever reached.
    test "sends everything again to a client whose place no row could carry" do
      seed(200)

      forged = "99999999999999999999999.0"

      assert gap(forged, nil) == {:full_resync, :cursor}
    end

    test "sends everything again when the client's place predates the log" do
      seed(200)

      [{tx, _seq}] = places()

      assert gap(Cursor.encode(tx - 1, 0), nil) == {:full_resync, :retention}
    end

    test "sends everything again when the log holds nothing to answer with" do
      assert gap(Cursor.encode(200, 1), nil) == {:full_resync, :retention}
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

      assert gap(Cursor.encode(tx, seq), nil) == {:full_resync, :gap_too_large}
    end

    test "replays a gap that fits" do
      seed_many(3)

      [{tx, seq} | _rest] = places()

      assert {:ok, effects, nil} = gap(Cursor.encode(tx, seq), nil)
      assert length(effects) == 2
    end

    test "sends everything again when the gap spans a change of model" do
      seed(200)
      seed(201)
      seed(202, "written under another model")

      [{tx, seq}, _second, _third] = places()

      # The gap is refused WHOLE, not up to the deploy: a replay stopping short would leave the
      # client holding rows of one model and a place that says it holds rows of both.
      assert gap(Cursor.encode(tx, seq), nil) == {:full_resync, :model_hash}
    end

    test "answers the grants a client held before one was revoked while it was away" do
      actor = user("catchup_1@example.com")
      resource = DB.create!(PolicyModule1.new())

      Auth.grant_role(actor, resource, :viewer)
      revoked = stored_grant(actor.id)
      Auth.revoke_role(actor, resource, :viewer)

      clear_log()

      seed(200)

      [{tx, seq}] = places()

      seed_grant(201, "del_entity", revoked)

      assert {:ok, [_effect], [grant]} = gap(Cursor.encode(tx, seq), actor.id)
      assert grant.id == revoked.id
      assert grant.role == :viewer
      assert grant.user_id == actor.id
    end

    test "answers no grants for a client whose own grants did not change" do
      actor = user("catchup_2@example.com")
      other = user("catchup_3@example.com")
      resource = DB.create!(PolicyModule1.new())

      Auth.grant_role(other, resource, :viewer)
      other_grant = stored_grant(other.id)

      clear_log()

      seed(200)

      [{tx, seq}] = places()

      seed_grant(201, "del_entity", other_grant)

      assert {:ok, [_effect], nil} = gap(Cursor.encode(tx, seq), actor.id)
    end

    test "answers no grants for an anonymous client" do
      actor = user("catchup_4@example.com")
      resource = DB.create!(PolicyModule1.new())

      Auth.grant_role(actor, resource, :viewer)
      grant = stored_grant(actor.id)

      clear_log()

      seed(200)

      [{tx, seq}] = places()

      seed_grant(201, "del_entity", grant)

      assert {:ok, [_effect], nil} = gap(Cursor.encode(tx, seq), nil)
    end

    test "answers no grants when the gap holds none" do
      actor = user("catchup_5@example.com")

      clear_log()

      seed(200)
      seed(201)

      [{tx, seq}, _second] = places()

      assert {:ok, [_effect], nil} = gap(Cursor.encode(tx, seq), actor.id)
    end

    # The model door answers first, so a grant effect is never compared as a module against a
    # label a newer peer wrote.
    test "refuses a mixed-model gap before looking at grants" do
      actor = user("catchup_6@example.com")
      resource = DB.create!(PolicyModule1.new())

      Auth.grant_role(actor, resource, :viewer)
      grant = stored_grant(actor.id)

      clear_log()

      seed(200)

      [{tx, seq}] = places()

      seed(201, "written under another model")
      seed_grant(202, "del_entity", grant)

      assert gap(Cursor.encode(tx, seq), actor.id) == {:full_resync, :model_hash}
    end

    test "replays a gap whose effects were all written under the current model" do
      seed(199, "written under another model")
      seed(200)
      seed(201)

      [_pruned, {tx, seq}, _second] = places()

      # The effect from before the client's place is of another model and is none of its business:
      # what it was away for is what comes after.
      assert {:ok, [effect], nil} = gap(Cursor.encode(tx, seq), nil)
      assert effect.tx == 201
    end
  end
end
