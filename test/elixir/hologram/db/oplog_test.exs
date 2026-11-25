defmodule Hologram.DB.OplogTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.Oplog

  alias Hologram.Auth.Context
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity.Model
  alias Hologram.Mutation.Ref
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  @replica_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e11"
  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @target_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"

  defp next_seq do
    {:ok, %Postgrex.Result{rows: [[seq]]}} =
      Connection.query(~s|SELECT "hologram_system"."next_seq"()|)

    seq
  end

  # Whether this connection holds the serial lock, shared. An advisory key of 64 bits shows in
  # pg_locks as its high and low halves.
  defp holds_serial_lock? do
    <<class_id::32, object_id::32>> = <<serial_lock_key()::signed-64>>

    statement = """
    SELECT EXISTS (
      SELECT 1 FROM pg_locks
      WHERE locktype = 'advisory' AND classid = $1 AND objid = $2 AND objsubid = 1
        AND mode = 'ShareLock' AND granted AND pid = pg_backend_pid()
    )
    """

    {:ok, %Postgrex.Result{rows: [[held?]]}} = Connection.query(statement, [class_id, object_id])

    held?
  end

  defp seqs do
    statement = ~s|SELECT "seq" FROM "hologram_system"."oplog" ORDER BY "seq"|

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [seq] -> seq end)
  end

  defp rows do
    statement = """
    SELECT "op", "type", "entity_id", "data", "model_hash", "mutation_ref", "actor_id",
           "revisions", "old"
    FROM "hologram_system"."oplog"
    ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [
                        op,
                        type,
                        entity_id,
                        data,
                        model_hash,
                        mutation_ref,
                        actor_id,
                        revisions,
                        old
                      ] ->
      %{
        actor_id: Codec.decode(actor_id, :uuid),
        data: data,
        entity_id: Codec.decode(entity_id, :uuid),
        model_hash: model_hash,
        mutation_ref: mutation_ref,
        old: old,
        op: op,
        revisions: revisions,
        type: type
      }
    end)
  end

  defp unsent_seqs(sent_through, unsent) do
    sent_through
    |> read_unsent(unsent)
    |> Enum.map(& &1.seq)
  end

  defp seed(
         tx,
         op,
         type_label,
         entity_id,
         data \\ nil,
         revisions \\ nil,
         mutation_ref \\ nil,
         old \\ nil
       ) do
    statement = """
    INSERT INTO "hologram_system"."oplog"
      ("op", "type", "entity_id", "data", "tx", "model_hash", "revisions", "mutation_ref", "old")
    VALUES ($1, $2, $3, $4, $5, 'seeded', $6, $7, $8)
    RETURNING "seq"
    """

    params = [
      op,
      type_label,
      Codec.encode(entity_id, :uuid),
      data,
      tx,
      revisions,
      mutation_ref,
      old
    ]

    {:ok, %Postgrex.Result{rows: [[seq]]}} = Connection.query(statement, params)

    seq
  end

  describe "next_seq()" do
    test "holds the serial lock from the first serial on" do
      refute holds_serial_lock?()

      next_seq()

      assert holds_serial_lock?()
    end

    test "hands out rising serials" do
      first = next_seq()

      assert next_seq() > first
    end

    test "takes the lock again after a rolled back savepoint gave it up" do
      {:error, :undone} =
        Connection.transaction(fn ->
          next_seq()

          assert holds_serial_lock?()

          Connection.rollback(:undone)
        end)

      refute holds_serial_lock?()

      next_seq()

      assert holds_serial_lock?()
    end

    test "numbers an effect appended without one" do
      serial = last_serial()

      refute holds_serial_lock?()

      :ok = append([%{op: :del_entity, entity_type: Module2, entity_id: @entity_id, data: %{}}])

      assert holds_serial_lock?()
      assert [seq] = seqs()
      assert seq > serial
    end
  end

  describe "last_serial/0" do
    # Other tests take serials meanwhile, so the one handed out here is at or below it, and the next
    # one above it.
    test "returns the highest serial handed out, also one no entry holds" do
      serial = next_seq()
      last = last_serial()

      assert last >= serial
      assert next_seq() > last
    end
  end

  describe "log_id/0" do
    # The test database was claimed when the suite started, so its marker row is there.
    test "returns the id of the log as 32 hex digits" do
      assert log_id() =~ ~r/\A[0-9a-f]{32}\z/
    end

    test "returns the same id on every read" do
      assert log_id() == log_id()
    end

    # A crash and a promoted standby leave the run's row empty, and the row put back names a new
    # run.
    test "returns another id once the server names a new run" do
      log_id = log_id()

      {:ok, _result} =
        Connection.query(~s|UPDATE "hologram_system"."server_run" SET "run" = gen_random_uuid()|)

      refute log_id() == log_id
    end

    test "returns another id once the marker names a new log" do
      log_id = log_id()

      {:ok, _result} =
        Connection.query(~s|UPDATE "hologram_system"."database" SET "log_id" = gen_random_uuid()|)

      refute log_id() == log_id
    end

    # A restore runs the view's query again, since a dump carries the query and not the row.
    test "returns another id once the database is restored as a new copy" do
      log_id = log_id()

      {:ok, _result} =
        Connection.query(~s|REFRESH MATERIALIZED VIEW "hologram_system"."database_copy"|)

      refute log_id() == log_id
    end

    test "returns nil while the server names no run" do
      {:ok, _result} = Connection.query(~s|DELETE FROM "hologram_system"."server_run"|)

      assert log_id() == nil
    end
  end

  describe "populate_database_copy/0" do
    test "fills the view a schema-only restore leaves empty" do
      {:ok, _result} =
        Connection.query(
          ~s|REFRESH MATERIALIZED VIEW "hologram_system"."database_copy" WITH NO DATA|
        )

      assert populate_database_copy() == :ok

      assert log_id() =~ ~r/\A[0-9a-f]{32}\z/
    end

    test "leaves a filled view as it is" do
      log_id = log_id()

      assert populate_database_copy() == :ok

      assert log_id() == log_id
    end

    # Two nodes starting together would otherwise both find the view empty, and the second filling
    # would name a new copy under the first's cursors. The lock is held for the transaction, which
    # here is the test's own.
    test "checks the view under a lock nodes take turns on" do
      assert populate_database_copy() == :ok

      statement = """
      SELECT EXISTS (
        SELECT 1 FROM pg_locks
        WHERE locktype = 'advisory' AND classid = $1 AND objid = $2 AND objsubid = 1
          AND mode = 'ExclusiveLock' AND granted AND pid = pg_backend_pid()
      )
      """

      <<class_id::32, object_id::32>> = <<4_596_668_662_837_798_245::signed-64>>

      assert {:ok, %Postgrex.Result{rows: [[true]]}} =
               Connection.query(statement, [class_id, object_id])
    end
  end

  describe "rotate_log_id/1" do
    test "gives the log a new id" do
      log_id = log_id()

      assert rotate_log_id(log_id) == :ok

      assert log_id() =~ ~r/\A[0-9a-f]{32}\z/
      refute log_id() == log_id
    end

    test "leaves an id that has moved already" do
      log_id = log_id()
      :ok = rotate_log_id(log_id)
      rotated = log_id()

      assert rotate_log_id(log_id) == :ok

      assert log_id() == rotated
    end
  end

  describe "run_log_id/1" do
    test "returns the log id a run was read under" do
      {_high, _running, run} = serials_in_flight()

      assert run_log_id(run) == log_id()
    end
  end

  describe "place/1" do
    test "returns the place before the first entry for no entry" do
      assert place(nil) == {0, 0, 0}
    end

    test "returns the entry's seq, transaction and time in microseconds" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      [entry] = read_after(0, 10)

      assert place(entry) ==
               {entry.seq, 200, DateTime.to_unix(entry.inserted_at, :microsecond)}
    end
  end

  describe "holds_place?/1" do
    test "holds the place before the first entry" do
      assert holds_place?({0, 0, 0})
    end

    test "holds the place of an entry it holds" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      [entry] = read_after(0, 10)

      assert holds_place?(place(entry))
    end

    test "doesn't hold a place no entry is at" do
      seq = seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      refute holds_place?({seq + 1, 200, 0})
    end

    # Another entry at the place's seq is one a server that lost the first one's commit wrote.
    test "doesn't hold a place another entry is at" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      [entry] = read_after(0, 10)
      {seq, tx, inserted_at} = place(entry)

      refute holds_place?({seq, tx + 1, inserted_at})
      refute holds_place?({seq, tx, inserted_at + 1})
    end
  end

  describe "replica_seqs_after/2" do
    test "returns each replica's highest batch with an entry above the given seq" do
      entity_id = Hologram.Entity.generate_id()

      first =
        seed(200, "patch_entity", "Module2", entity_id, nil, nil, %{
          "replica_id" => "a",
          "seq" => 3
        })

      seed(201, "patch_entity", "Module2", entity_id, nil, nil, %{"replica_id" => "a", "seq" => 5})

      seed(202, "patch_entity", "Module2", entity_id, nil, nil, %{"replica_id" => "a", "seq" => 4})

      seed(201, "patch_entity", "Module2", entity_id, nil, nil, %{"replica_id" => "b", "seq" => 9})

      assert replica_seqs_after(first - 1) == %{"a" => 5, "b" => 9}
    end

    test "leaves out the batches with entries only at the given seq and below it" do
      entity_id = Hologram.Entity.generate_id()

      first =
        seed(200, "patch_entity", "Module2", entity_id, nil, nil, %{
          "replica_id" => "a",
          "seq" => 3
        })

      second =
        seed(201, "patch_entity", "Module2", entity_id, nil, nil, %{
          "replica_id" => "b",
          "seq" => 9
        })

      assert replica_seqs_after(first) == %{"b" => 9}
      assert replica_seqs_after(second) == %{}
    end

    test "passes over the effects of no batch" do
      seq = seed(201, "patch_entity", "Module2", Hologram.Entity.generate_id())

      assert replica_seqs_after(seq - 1) == %{}
    end

    test "returns the batches with entries in the given ranges, and none of the rest at or below the given seq" do
      entity_id = Hologram.Entity.generate_id()

      in_range =
        seed(200, "patch_entity", "Module2", entity_id, nil, nil, %{
          "replica_id" => "a",
          "seq" => 3
        })

      sent =
        seed(201, "patch_entity", "Module2", entity_id, nil, nil, %{
          "replica_id" => "b",
          "seq" => 9
        })

      seed(202, "patch_entity", "Module2", entity_id, nil, nil, %{"replica_id" => "c", "seq" => 2})

      assert replica_seqs_after(sent, [{in_range, in_range}]) == %{"a" => 3, "c" => 2}
    end
  end

  describe "read_after/2" do
    test "returns nothing when the log holds no effects" do
      assert read_after(0, 10) == []
    end

    test "returns the effects written after the given seq" do
      first_seq = seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      assert [event] = read_after(first_seq, 10)
      assert event.entity_id == @target_id
    end

    test "returns the time the effect was written" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert [%{inserted_at: %DateTime{}}] = read_after(0, 10)
    end

    test "returns the revisions the effect was stored with" do
      seed(200, "patch_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, nil, %{a: 5})

      assert [event] = read_after(0, 10)
      assert event.revisions == %{"a" => 5}
    end

    # An old reference names a row the move took this one away from, so it is an id that moved -
    # as fixed in size as an edge's target, and kept for the same reason while the payload is not.
    test "returns the old references the effect was stored with, without the payload" do
      data = %{"c_id" => @target_id}
      old = %{"c_id" => @entity_id}

      seed(
        200,
        "patch_entity",
        "Hologram.Test.Fixtures.Entity.Module3",
        @entity_id,
        data,
        nil,
        nil,
        old
      )

      assert [event] = read_after(0, 10)
      assert event.old == old
      assert event.data == nil
    end

    test "returns no old references for an effect stored without them" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert [event] = read_after(0, 10)
      assert event.old == nil
    end

    # The batch an effect belongs to travels with it, where the payload does not: it is a bounded
    # pair rather than a value of the app's own size, and it is what tells a reader which of the
    # effects it is being told about are its own doing.
    test "returns the batch the effect was written by" do
      ref = %{"replica_id" => @replica_id, "seq" => 7}

      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, nil, nil, ref)

      assert [event] = read_after(0, 10)
      assert event.mutation_ref == ref
    end

    test "returns nothing for the batch of an effect no batch wrote" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert [event] = read_after(0, 10)
      assert event.mutation_ref == nil
    end

    test "leaves out the effect at the given seq, which the reader already has" do
      seq = seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert read_after(seq, 10) == []
    end

    # The payload is what makes an effect's size vary - a delete carries none, a wide entity's put
    # carries kilobytes - so leaving it out is what lets the caller bound a gap by counting.
    test "leaves the payload behind, since a replay reads values from the rows" do
      seq =
        seed(200, "patch_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{
          "c" => "x"
        })

      assert [event] = read_after(0, 10)
      assert event.data == nil

      # The live read, which diffs against values, still carries it.
      assert [windowed] = read_unsent(seq - 1, [])
      assert windowed.data == %{"c" => "x"}
    end

    # An edge names a second row that moved - its target - in two short strings whatever the
    # entity, so its payload stays without making the size vary.
    test "returns the payload of an edge" do
      data = %{"relationship" => "a", "target_id" => @target_id}

      seed(200, "add_relationship", "Hologram.Test.Fixtures.Entity.Module3", @entity_id, data)
      seed(200, "del_relationship", "Hologram.Test.Fixtures.Entity.Module3", @entity_id, data)

      assert [added, removed] = read_after(0, 10)
      assert added.data == data
      assert removed.data == data
    end

    # Not a page - nothing resumes from where this stopped. It is what keeps a reader from pulling
    # an unbounded tail into memory, and its caller reads one past its own cap to learn there is
    # more rather than to fetch it.
    test "returns no more than the limit asks for" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(201, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      assert [event] = read_after(0, 1)
      assert event.tx == 200
    end

    # Serials are handed out as saves write, so the log's order is theirs, whichever transaction
    # wrote what.
    test "returns the effects in seq order, whatever their transactions" do
      seed(201, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert [first, second] = read_after(0, 10)
      assert first.entity_id == @target_id
      assert second.entity_id == @entity_id
    end
  end

  describe "count_after/3" do
    test "counts the effects written after the given seq" do
      first_seq = seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(201, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      assert count_after(first_seq - 1, 10, "seeded") == {2, false}
      assert count_after(first_seq, 10, "seeded") == {1, false}
    end

    test "counts no further than the limit" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(201, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      assert count_after(0, 1, "seeded") == {1, false}
    end

    # Every row this suite seeds is written under the model hash "seeded".
    test "answers whether an effect counted was written under another model" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert count_after(0, 10, "current") == {1, true}
    end

    test "answers nothing counted for a seq past every effect" do
      seq = seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert count_after(seq, 10, "seeded") == {0, false}
    end
  end

  describe "any_data_match?/2" do
    test "answers whether the data of any effect of the given seqs holds the match" do
      seed(200, "del_entity", "Hologram.Auth.RoleGrant", @entity_id, %{"user_id" => "a"})
      seed(200, "del_entity", "Hologram.Auth.RoleGrant", @target_id, %{"user_id" => "b"})

      [first_seq, second_seq] =
        0
        |> read_after(10)
        |> Enum.map(& &1.seq)

      assert any_data_match?([first_seq, second_seq], %{"user_id" => "b"})
      refute any_data_match?([first_seq], %{"user_id" => "b"})
    end

    test "matches nothing of a seq the log doesn't hold" do
      seed(200, "del_entity", "Hologram.Auth.RoleGrant", @entity_id, %{"user_id" => "a"})

      [%{seq: seq}] = read_after(0, 10)

      refute any_data_match?([seq + 1], %{"user_id" => "a"})
    end

    test "matches nothing for no seqs" do
      refute any_data_match?([], %{"user_id" => "a"})
    end
  end

  describe "read_data/1" do
    test "returns the payload of each effect by its seq" do
      seed(200, "patch_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{"c" => "x"})

      seed(200, "put_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id, %{"c" => "y"})

      [first_seq, second_seq] =
        0
        |> read_after(10)
        |> Enum.map(& &1.seq)

      assert read_data([first_seq, second_seq]) == %{
               first_seq => %{"c" => "x"},
               second_seq => %{"c" => "y"}
             }
    end

    test "returns the payload of an edge" do
      data = %{"relationship" => "a", "target_id" => @target_id}

      seed(200, "add_relationship", "Hologram.Test.Fixtures.Entity.Module3", @entity_id, data)

      [%{seq: seq}] = read_after(0, 10)

      assert read_data([seq]) == %{seq => data}
    end

    test "leaves out a seq the log doesn't hold" do
      seed(200, "patch_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{"c" => "x"})

      [%{seq: seq}] = read_after(0, 10)

      assert read_data([seq, seq + 1]) == %{seq => %{"c" => "x"}}
    end

    test "returns nothing for no seqs" do
      assert read_data([]) == %{}
    end
  end

  describe "read_type_after/3" do
    test "returns nothing when the log holds no effects of the given type" do
      seed(200, "put_entity", "Hologram.Test.Fixtures.Entity.Module14", @entity_id, %{c: "other"})

      assert read_type_after(Module2, 0, %{}) == []
    end

    test "returns the effects of the given type since the given seq, in seq order" do
      first_seq =
        seed(200, "put_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{
          c: "before"
        })

      seed(201, "put_entity", "Hologram.Test.Fixtures.Entity.Module14", @target_id, %{c: "other"})
      seed(202, "put_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id, %{c: "after"})
      seed(203, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{c: "gone"})

      assert [put, delete] = read_type_after(Module2, first_seq, %{})

      assert put.entity_id == @target_id
      assert put.op == :put_entity
      assert put.data == %{"c" => "after"}

      assert delete.entity_id == @entity_id
      assert delete.op == :del_entity
      assert delete.data == %{"c" => "gone"}
    end

    test "returns the old references the effect was stored with" do
      data = %{"c_id" => @target_id}
      old = %{"c_id" => @entity_id}

      seed(
        200,
        "patch_entity",
        "Hologram.Test.Fixtures.Entity.Module3",
        @entity_id,
        data,
        nil,
        nil,
        old
      )

      assert [effect] = read_type_after(Module3, 0, %{})
      assert effect.old == old
    end

    test "returns no old references for an effect stored without them" do
      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{c: "gone"})

      assert [effect] = read_type_after(Module2, 0, %{})
      assert effect.old == nil
    end

    test "returns nothing written at or before the given seq" do
      seq =
        seed(200, "put_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{
          c: "before"
        })

      assert read_type_after(Module2, seq, %{}) == []
    end

    test "returns only the effects whose data holds every pair of the given match" do
      seed(200, "put_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{c: "wanted"})
      seed(201, "put_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id, %{c: "other"})

      assert [effect] = read_type_after(Module2, 0, %{c: "wanted"})
      assert effect.entity_id == @entity_id
    end
  end

  describe "read_unsent/2" do
    test "returns nothing when nothing was written above the highest sent" do
      assert read_unsent(last_serial(), []) == []
    end

    test "returns the effects above the highest sent" do
      seq = seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert [event] = read_unsent(seq - 1, [])
      assert event.op == :del_entity
      assert event.type == Module2
      assert event.entity_id == @entity_id
      assert event.model_hash == "seeded"
    end

    test "returns the revisions the effect was stored with" do
      seq =
        seed(200, "patch_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, nil, %{
          a: 5
        })

      assert [event] = read_unsent(seq - 1, [])
      assert event.revisions == %{"a" => 5}
    end

    test "returns the old references the effect was stored with" do
      old = %{"c_id" => @target_id}

      seq =
        seed(
          200,
          "patch_entity",
          "Hologram.Test.Fixtures.Entity.Module3",
          @entity_id,
          nil,
          nil,
          nil,
          old
        )

      assert [event] = read_unsent(seq - 1, [])
      assert event.old == old
    end

    test "returns no old references for an effect stored without them" do
      seq = seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert [event] = read_unsent(seq - 1, [])
      assert event.old == nil
    end

    test "returns the batch the effect was written under" do
      seq =
        seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, nil, nil, %{
          replica_id: @replica_id,
          seq: 7
        })

      assert [event] = read_unsent(seq - 1, [])
      assert event.mutation_ref == %{"replica_id" => @replica_id, "seq" => 7}
    end

    test "returns no batch for an effect written outside one" do
      seq = seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert [event] = read_unsent(seq - 1, [])
      assert event.mutation_ref == nil
    end

    test "leaves out the effect at the highest sent, which the reader already has" do
      seq = seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)

      assert read_unsent(seq, []) == []
    end

    test "returns the effects in the ranges not sent, and none of the rest at or below the highest sent" do
      [first, second, third, fourth, fifth] =
        Enum.map(
          200..204,
          &seed(&1, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
        )

      assert unsent_seqs(fourth, [{second, third}]) == [second, third, fifth]
      assert unsent_seqs(fifth, [{first, first}, {fourth, fourth}]) == [first, fourth]
    end

    test "returns the effects in many ranges not sent at once" do
      seqs =
        Enum.map(
          1..202,
          &seed(&1, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
        )

      every_other = Enum.take_every(seqs, 2)
      unsent = Enum.map(every_other, &{&1, &1})

      assert length(unsent) == 101
      assert unsent_seqs(List.last(seqs), unsent) == every_other
    end

    test "returns the effects in seq order, whatever their transactions" do
      first =
        seed(201, "put_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{"c" => "x"})

      seed(200, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id)
      seed(201, "del_entity", "Hologram.Test.Fixtures.Entity.Module2", @target_id)

      assert [put, delete, other_delete] = read_unsent(first - 1, [])
      assert {put.op, put.tx} == {:put_entity, 201}
      assert {delete.op, delete.tx} == {:del_entity, 200}
      assert other_delete.entity_id == @target_id
    end

    # A newer peer writing a seventh op is what a rolling deploy produces, and raising here would
    # take the dispatcher down mid-window - it restarts with no cursor and resumes at the final
    # limit, so everything between would be skipped rather than retried. Downstream is already
    # indifferent: what reads an op matches it against atoms and leaves an unknown one alone.
    test "keeps an op this build does not know as the label it was written with" do
      statement = """
      INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "tx", "model_hash")
      VALUES ('op_from_a_newer_build', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, 'seeded')
      RETURNING "seq"
      """

      params = [Codec.encode(@entity_id, :uuid), 200]

      {:ok, %Postgrex.Result{rows: [[seq]]}} = Connection.query(statement, params)

      assert [event] = read_unsent(seq - 1, [])
      assert event.op == "op_from_a_newer_build"
    end

    test "keeps an entity type this node has never compiled as the label it was written with" do
      # A name no test anywhere in the suite writes as an atom LITERAL: one that does makes the
      # atom exist for every test, and this one is about a type whose atom does not exist.
      seq = seed(200, "del_entity", "MyApp.TypeOnlyThisTestNames", @entity_id)

      assert [event] = read_unsent(seq - 1, [])
      assert event.type == "MyApp.TypeOnlyThisTestNames"
    end

    test "keeps data keys as they were written" do
      seq =
        seed(200, "patch_entity", "Hologram.Test.Fixtures.Entity.Module2", @entity_id, %{
          "never_compiled" => 1
        })

      assert [event] = read_unsent(seq - 1, [])
      assert event.data == %{"never_compiled" => 1}
    end
  end

  describe "append/1" do
    test "appends nothing for no effects" do
      assert append([]) == :ok
      assert rows() == []
    end

    # PostgreSQL binds at most 65,535 parameters per statement, so this many rows can't go in as one.
    test "appends more effects than one statement can bind, in order" do
      effects =
        Enum.map(1..7_300, fn index ->
          %{op: :patch_entity, entity_type: Module2, entity_id: @entity_id, data: %{b: index}}
        end)

      assert append(effects) == :ok

      assert Enum.map(rows(), & &1.data["b"]) == Enum.to_list(1..7_300)
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

    test "records a deletion with the row it removed" do
      effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id, data: %{c: "gone"}}

      assert append([effect]) == :ok

      assert [%{data: %{"c" => "gone"}, op: "del_entity"}] = rows()
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
        %{op: :del_entity, entity_type: Module2, entity_id: @entity_id, data: %{c: "gone"}}
      ]

      assert append(effects) == :ok

      assert ["patch_entity", "del_entity"] = Enum.map(rows(), & &1.op)
    end

    test "stamps the model the values were written under" do
      effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id, data: %{c: "gone"}}

      assert append([effect]) == :ok

      assert [%{model_hash: model_hash}] = rows()
      assert model_hash == Model.hash()
    end

    test "records the acting user" do
      user_id = "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e11"

      Context.with_actor(user_id, fn ->
        effect = %{
          op: :del_entity,
          entity_type: Module2,
          entity_id: @entity_id,
          data: %{c: "gone"}
        }

        assert append([effect]) == :ok
      end)

      assert [%{actor_id: ^user_id}] = rows()
    end

    test "records no actor for a write the framework made itself" do
      effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id, data: %{c: "gone"}}

      assert append([effect]) == :ok

      assert [%{actor_id: nil}] = rows()
    end

    test "records the batch an effect was written under" do
      effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id, data: %{c: "gone"}}

      assert Ref.with_ref(%{replica_id: @replica_id, seq: 7}, fn -> append([effect]) end) == :ok

      assert [%{mutation_ref: %{"replica_id" => @replica_id, "seq" => 7}}] = rows()
    end

    test "records no batch for an effect written outside one" do
      effect = %{op: :del_entity, entity_type: Module2, entity_id: @entity_id, data: %{c: "gone"}}

      assert append([effect]) == :ok

      assert [%{mutation_ref: nil}] = rows()
    end

    test "stores the revisions an effect carries" do
      effect = %{
        op: :put_entity,
        entity_type: Module2,
        entity_id: @entity_id,
        data: %{a: true},
        revisions: %{a: 5}
      }

      assert append([effect]) == :ok

      assert [%{revisions: revisions}] = rows()
      assert revisions == %{"a" => 5}
    end

    test "stores no revisions for an effect carrying none" do
      effect = %{
        op: :add_relationship,
        entity_type: Module3,
        entity_id: @entity_id,
        relationship: :a,
        target_id: @target_id
      }

      assert append([effect]) == :ok

      assert [%{revisions: revisions}] = rows()
      assert revisions == nil
    end

    test "stores the old references a patch carries, an unset one included" do
      effect = %{
        op: :patch_entity,
        entity_type: Module3,
        entity_id: @entity_id,
        data: %{b_id: @entity_id, c_id: @target_id},
        old: %{b_id: nil, c_id: @entity_id}
      }

      assert append([effect]) == :ok

      assert [%{old: old}] = rows()
      assert old == %{"b_id" => nil, "c_id" => @entity_id}
    end

    test "stores no old references for an effect carrying none" do
      effect = %{op: :patch_entity, entity_type: Module2, entity_id: @entity_id, data: %{c: "x"}}

      assert append([effect]) == :ok

      assert [%{old: nil}] = rows()
    end

    test "stores no old references for an effect whose old references are nil" do
      effect = %{
        op: :patch_entity,
        entity_type: Module2,
        entity_id: @entity_id,
        data: %{c: "x"},
        old: nil
      }

      assert append([effect]) == :ok

      assert [%{old: nil}] = rows()
    end

    # Half of a pair. Its twin is wire_data_test.exs's "leaves out a server-only attribute whose
    # real value the row is holding", and together they state the design: the LOG is complete and
    # the WIRE is filtered. Which one is allowed to show a value is a fact about the model now, so
    # only the wire can decide it - a strip at write time would classify a permanent log by a flag
    # that can be added to or removed from an attribute later. Breaking either half names which of
    # the two rules was violated.
    test "stores the value of a server-only attribute" do
      effect = %{
        op: :put_entity,
        entity_type: Module14,
        entity_id: @entity_id,
        data: %{email: "user@test.com", password_hash: "hashed_secret_v1"}
      }

      assert append([effect]) == :ok

      assert [%{data: data}] = rows()
      assert data == %{"email" => "user@test.com", "password_hash" => "hashed_secret_v1"}
    end
  end
end
