defmodule Hologram.DB.OutboxTest do
  # Grouped rather than merely async - pruning takes an advisory lock on a fixed key, which is one
  # lock for the whole database rather than one per connection. It is transaction-scoped, and the
  # sandbox runs each test inside a transaction, so whoever takes it holds it until their test
  # ends, and any other module pruning meanwhile finds it taken and deletes nothing. A group is
  # what keeps the two modules that prune off each other while both stay async.
  #
  # Sync would serialize them too, and must not be used: the sync phase is where the unsandboxed
  # tests run, and their COMMITTED rows are visible to anything sandboxed running beside them.
  use Hologram.Test.DatabaseCase, async: true, group: :outbox_pruning

  import Hologram.DB.Outbox

  alias Hologram.Auth.Context
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity.Model
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @target_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"

  defp places do
    statement = ~s|SELECT "tx", "seq" FROM "hologram_system"."outbox" ORDER BY "tx", "seq"|

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [tx, seq] -> {tx, seq} end)
  end

  defp rows do
    statement = """
    SELECT "op", "type", "entity_id", "data", "model_hash", "mutation_ref", "actor_id"
    FROM "hologram_system"."outbox"
    ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [op, type, entity_id, data, model_hash, mutation_ref, actor_id] ->
      %{
        actor_id: Codec.decode(actor_id, :uuid),
        data: data,
        entity_id: Codec.decode(entity_id, :uuid),
        model_hash: model_hash,
        mutation_ref: mutation_ref,
        op: op,
        type: type
      }
    end)
  end

  defp seed(tx, op, type_label, entity_id, data \\ nil) do
    statement = """
    INSERT INTO "hologram_system"."outbox" ("op", "type", "entity_id", "data", "tx", "model_hash")
    VALUES ($1, $2, $3, $4, $5, 'seeded')
    """

    params = [op, type_label, Codec.encode(entity_id, :uuid), data, tx]

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end

  # An effect written the given number of seconds ago. Both this and the prune read `now()`, which
  # inside a transaction is the transaction's own start - so the ages here are exact, not racing.
  defp seed_aged(entity_id, seconds_ago) do
    statement = """
    INSERT INTO "hologram_system"."outbox"
      ("op", "type", "entity_id", "tx", "model_hash", "inserted_at")
    VALUES ('del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, 'seeded',
            now() - make_interval(secs => $3::double precision))
    """

    params = [Codec.encode(entity_id, :uuid), 200, seconds_ago]

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end

  describe "current_xmin/0" do
    test "returns the transaction id below which every transaction has finished" do
      {:ok, %Postgrex.Result{rows: [[writing_tx]]}} =
        Connection.query("SELECT pg_current_xact_id()")

      # The window's own transaction is in flight, so the edge cannot have passed it.
      assert current_xmin() <= writing_tx
    end
  end

  describe "oldest_place/0" do
    test "returns nothing when the log holds no effects" do
      assert oldest_place() == nil
    end

    test "returns the place of the effect nothing precedes" do
      seed(201, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      [oldest | _rest] = places()

      assert oldest_place() == oldest
    end
  end

  describe "prune/1" do
    test "removes the effects past the given age and keeps the rest" do
      seed_aged(@entity_id, 3_600)
      seed_aged(@target_id, 30)

      assert prune(60) == 1

      assert [event] = read_after(0, 0, 10)
      assert event.entity_id == @target_id
    end

    test "removes nothing when every effect is inside the window" do
      seed_aged(@entity_id, 30)

      assert prune(60) == 0
      assert length(read_after(0, 0, 10)) == 1
    end

    test "removes nothing from a log holding nothing" do
      assert prune(60) == 0
    end

    # That a SECOND node finds the lock held cannot be shown here - the sandbox gives every process
    # one connection, so a lock this test takes is a lock the prune already holds. What is shown is
    # that the prune asks for it at all, and that it is transaction-scoped: it is still held after
    # the statement, inside the transaction that ran it. Two real nodes contending belongs to the
    # cluster suite.
    test "asks for the lock that keeps two nodes from pruning at once" do
      seed_aged(@entity_id, 3_600)

      assert prune(60) == 1

      statement = """
      SELECT count(*) FROM pg_locks
      WHERE locktype = 'advisory' AND objid = $1 AND granted
      """

      # The key is written out again rather than read from the module on purpose: it must never
      # move once deployed, or two builds mid-rollout would prune past each other.
      {:ok, %Postgrex.Result{rows: [[held]]}} = Connection.query(statement, [0x484F_4C4F])

      assert held == 1
    end
  end

  describe "read_after/3" do
    test "returns nothing when the log holds no effects" do
      assert read_after(0, 0, 10) == []
    end

    test "returns the effects written after the given place" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      [{_tx, first_seq} | _rest] = places()

      assert [event] = read_after(200, first_seq, 10)
      assert event.entity_id == @target_id
    end

    test "leaves out the effect at the given place, which the reader already has" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      [{tx, seq}] = places()

      assert read_after(tx, seq, 10) == []
    end

    test "leaves out effects of transactions below the given place" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(202, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      assert [event] = read_after(201, 0, 10)
      assert event.entity_id == @target_id
    end

    # The payload is what makes an effect's size vary - a delete carries none, a wide entity's put
    # carries kilobytes - so leaving it out is what lets the caller bound a gap by counting.
    test "leaves the payload behind, since a replay reads values from the rows" do
      seed(200, "patch_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{"c" => "x"})

      assert [event] = read_after(0, 0, 10)
      refute Map.has_key?(event, :data)

      # The windowed read, which diffs against values, still carries it.
      assert [{200, [windowed]}] = read_window(200, 201)
      assert windowed.data == %{"c" => "x"}
    end

    # Not a page - nothing resumes from where this stopped. It is what keeps a reader from pulling
    # an unbounded tail into memory, and its caller reads one past its own cap to learn there is
    # more rather than to fetch it.
    test "returns no more than the limit asks for" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(201, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      assert [event] = read_after(0, 0, 1)
      assert event.tx == 200
    end

    test "returns the effects in the order a reader is told about them" do
      # Written in the reverse of the order they are read in, so insert order alone cannot produce
      # the answer - the earlier transaction comes first however late its rows were written.
      seed(201, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert [first, second] = read_after(0, 0, 10)
      assert first.entity_id == @entity_id
      assert second.entity_id == @target_id
    end
  end

  describe "read_window/2" do
    test "returns nothing when the window holds no effects" do
      assert read_window(1, 2) == []
    end

    test "returns the effects of transactions inside the window" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert [{200, [event]}] = read_window(200, 201)
      assert event.op == :del_entity
      assert event.type == Module2
      assert event.entity_id == @entity_id
      assert event.model_hash == "seeded"
    end

    test "leaves out transactions below the window" do
      seed(199, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert read_window(200, 300) == []
    end

    test "leaves out transactions at and above the window's upper edge" do
      seed(300, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert read_window(200, 300) == []
    end

    test "groups a transaction's effects together, in the order they happened" do
      seed(200, "put_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{"c" => "x"})
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(201, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      assert [{200, first_transaction}, {201, second_transaction}] = read_window(200, 202)
      assert Enum.map(first_transaction, & &1.op) == [:put_entity, :del_entity]
      assert Enum.map(second_transaction, & &1.op) == [:del_entity]
    end

    # A newer peer writing a seventh op is what a rolling deploy produces, and raising here would
    # take the dispatcher down mid-window - it restarts with no cursor and resumes at the log's
    # edge, so everything between would be skipped rather than retried. Downstream is already
    # indifferent: the diff matches ops against atoms, and the scoper reads only the type.
    test "keeps an op this build does not know as the label it was written with" do
      statement = """
      INSERT INTO "hologram_system"."outbox" ("op", "type", "entity_id", "tx", "model_hash")
      VALUES ('op_from_a_newer_build', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, 'seeded')
      """

      params = [Codec.encode(@entity_id, :uuid), 200]

      {:ok, _result} = Connection.query(statement, params)

      assert [{200, [event]}] = read_window(200, 201)
      assert event.op == "op_from_a_newer_build"
    end

    test "keeps an entity type this node has never compiled as the label it was written with" do
      # A name no test anywhere in the suite writes as an atom LITERAL: one that does makes the
      # atom exist for every test, and this one is about a type whose atom does not exist.
      seed(200, "del_entity", "MyApp.TypeOnlyThisTestNames", @entity_id)

      assert [{200, [event]}] = read_window(200, 201)
      assert event.type == "MyApp.TypeOnlyThisTestNames"
    end

    test "keeps data keys as they were written" do
      seed(200, "patch_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{
        "never_compiled" => 1
      })

      assert [{200, [event]}] = read_window(200, 201)
      assert event.data == %{"never_compiled" => 1}
    end
  end

  describe "append/1" do
    test "appends nothing for no effects" do
      assert append([]) == :ok
      assert rows() == []
    end

    test "records an entity's attributes under the type's declared name" do
      effect = %{
        op: :put_entity,
        entity_type: Module2,
        entity_id: @entity_id,
        data: %{a: true, b: 7, c: "xyz"}
      }

      assert append([effect]) == :ok

      assert [row] = rows()
      assert row.op == "put_entity"
      assert row.type == "Hologram.Test.Fixtures.Entity.Module2"
      assert row.entity_id == @entity_id
      assert row.data == %{"a" => true, "b" => 7, "c" => "xyz"}
    end

    test "records only the attributes a patch changed" do
      effect = %{
        op: :patch_entity,
        entity_type: Module2,
        entity_id: @entity_id,
        data: %{c: "updated"}
      }

      assert append([effect]) == :ok

      assert [%{data: %{"c" => "updated"}, op: "patch_entity"}] = rows()
    end

    test "records a deletion without data" do
      effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id}

      assert append([effect]) == :ok

      assert [%{data: nil, op: "del_entity"}] = rows()
    end

    test "records a relationship op with the edge it moved" do
      effect = %{
        op: :add_relationship,
        entity_type: Module3,
        entity_id: @entity_id,
        relationship: :a,
        target_id: @target_id
      }

      assert append([effect]) == :ok

      assert [row] = rows()
      assert row.op == "add_relationship"
      assert row.data == %{"relationship" => "a", "target_id" => @target_id}
    end

    test "records each effect of a transaction in the order given" do
      effects = [
        %{op: :patch_entity, entity_type: Module2, entity_id: @entity_id, data: %{c: "first"}},
        %{op: :del_entity, entity_type: Module2, entity_id: @entity_id}
      ]

      assert append(effects) == :ok

      assert ["patch_entity", "del_entity"] = Enum.map(rows(), & &1.op)
    end

    test "stamps the model the values were written under" do
      effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id}

      assert append([effect]) == :ok

      assert [%{model_hash: model_hash}] = rows()
      assert model_hash == Model.hash()
    end

    test "records the acting user" do
      user_id = "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e11"

      Context.with_actor(user_id, fn ->
        effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id}

        assert append([effect]) == :ok
      end)

      assert [%{actor_id: ^user_id}] = rows()
    end

    test "records no actor for a write the framework made itself" do
      effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id}

      assert append([effect]) == :ok

      assert [%{actor_id: nil}] = rows()
    end

    # Provenance beyond the actor arrives with mutations, which do not exist yet.
    test "records no mutation reference" do
      effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id}

      assert append([effect]) == :ok

      assert [%{mutation_ref: nil}] = rows()
    end

    test "never records the value of a server-only attribute" do
      effect = %{
        op: :put_entity,
        entity_type: Module14,
        entity_id: @entity_id,
        data: %{email: "user@test.com", password_hash: "hashed_secret_v1"}
      }

      assert append([effect]) == :ok

      assert [%{data: data}] = rows()
      assert data == %{"email" => "user@test.com"}

      {:ok, %Postgrex.Result{rows: [[log]]}} =
        Connection.query(~s|SELECT "data"::text FROM "hologram_system"."outbox"|)

      refute log =~ "hashed_secret_v1"
    end
  end
end
