defmodule Hologram.DB.EntityOperationsContentionTest do
  # A delete takes the row's outgoing edges with it, and an edge added from the row while it runs
  # must not refuse it. The delete locks the row before its edges go, so a write that added an edge
  # first is waited for and its edge goes with the row, and one that comes after waits for the
  # delete and fails once the row is gone. That needs commits other sessions see, which the
  # sandboxed suite can't give.
  #
  # Each race is staged with a third session holding a row the delete reaches for, so the delete
  # always parks where the other write has to meet it, and the wait is asserted in PostgreSQL itself.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection, so the
  # tier's modules run one at a time to keep the server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  defp add_edge(source, target) do
    :ok = EntityOperations.add_relationship(Module3, source.id, :a, target.id)
  end

  defp create_source(scratch) do
    route(scratch, fn ->
      {:ok, required_target} = EntityOperations.create(Module1.new())

      {:ok, source} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> EntityOperations.create()

      source
    end)
  end

  defp create_target(scratch) do
    route(scratch, fn ->
      {:ok, target} =
        %{c: "some text"}
        |> Module2.new()
        |> EntityOperations.create()

      target
    end)
  end

  # The ids of the targets the join table holds an edge to from the given source, sorted.
  defp edge_target_ids(scratch, source) do
    statement = ~s|SELECT "target_id" FROM #{qualified_join_table()} WHERE "source_id" = $1|

    {:ok, %Postgrex.Result{rows: rows}} =
      route(scratch, fn -> Connection.query(statement, [Codec.encode(source.id, :uuid)]) end)

    rows
    |> Enum.map(fn [target_id] -> Codec.decode(target_id, :uuid) end)
    |> Enum.sort()
  end

  defp hold(lock, write, test_pid) do
    fn ->
      lock.()

      send(test_pid, :holding)

      receive do
        :release -> write.()
      end
    end
  end

  defp join_table, do: DB.join_table_name(Module3, :a)

  # What the oplog holds, in order, as {op, entity id, target id} - nil for an entry naming no
  # target.
  defp oplog_entries(scratch) do
    statement = ~s|SELECT "op", "entity_id", "data" FROM "hologram_system"."oplog" ORDER BY "seq"|

    {:ok, %Postgrex.Result{rows: rows}} = route(scratch, fn -> Connection.query(statement) end)

    Enum.map(rows, fn [op, entity_id, data] ->
      {op, Codec.decode(entity_id, :uuid), data["target_id"]}
    end)
  end

  defp on_own_session(scratch_opts, fun) do
    {:ok, session} = Postgrex.start_link(scratch_opts)

    route(session, fun)
  end

  defp oplog_seqs(scratch, op, entity) do
    statement =
      ~s|SELECT "seq" FROM "hologram_system"."oplog" WHERE "op" = $1 AND "entity_id" = $2|

    {:ok, %Postgrex.Result{rows: rows}} =
      route(scratch, fn ->
        Connection.query(statement, [op, Codec.encode(entity.id, :uuid)])
      end)

    List.flatten(rows)
  end

  defp qualified_join_table do
    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(join_table())}"
  end

  # The error a database refusal raises, returned as a value - a task that raised would take the
  # test down with it, hiding which refusal it was.
  defp refusal_or_result(fun) do
    fun.()
  rescue
    error in Postgrex.Error -> error
  end

  # Trusted code on a session of its own: it takes the given locks in a transaction, sends
  # :holding, and once the test lets go runs the given write and commits.
  defp start_holder(scratch_opts, lock, write, test_pid) do
    Task.async(fn ->
      on_own_session(scratch_opts, fn -> Connection.transaction(hold(lock, write, test_pid)) end)
    end)
  end

  # Trusted code on a session of its own, with no transaction but the verb's.
  defp start_write(scratch_opts, write) do
    Task.async(fn -> on_own_session(scratch_opts, fn -> refusal_or_result(write) end) end)
  end

  setup %{scratch: scratch} do
    route(scratch, fn -> SchemaReconciler.reconcile(DB.reconciliation_context()) end)

    :ok
  end

  test "an update that waited for a row's lock takes a serial above the write it waited for", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    target = create_target(scratch)

    # The holder has written the row and goes on to write it again once the other update waits, so
    # the serial the waiting update took before it blocked is below the holder's last one.
    holder =
      start_holder(
        scratch_opts,
        fn -> :ok = EntityOperations.update(Module2, target.id, c: "held") end,
        fn -> :ok = EntityOperations.update(Module2, target.id, c: "held again") end,
        self()
      )

    assert_receive :holding, 5_000

    waiter =
      start_write(scratch_opts, fn -> EntityOperations.update(Module2, target.id, c: "waited") end)

    wait_for_blocked_sessions(scratch_opts, 1)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    assert Task.await(waiter) == :ok

    stored = route(scratch, fn -> EntityOperations.get(Module2, target.id) end)

    patch_seqs =
      scratch
      |> oplog_seqs("patch_entity", target)
      |> Enum.sort()

    assert stored.c == "waited"
    assert length(patch_seqs) == 3
    assert stored.server_updated_seq == List.last(patch_seqs)
  end

  test "a delete takes with it an edge added from the row while it waited", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    source = create_source(scratch)
    [first_target, second_target] = [create_target(scratch), create_target(scratch)]

    route(scratch, fn -> add_edge(source, first_target) end)

    entries_before = oplog_entries(scratch)

    # The holder locks the row as the update verb does before it adds an edge, and adds one once
    # the delete waits on it.
    holder =
      start_holder(
        scratch_opts,
        fn -> EntityOperations.get(Module3, source.id, lock: :update) end,
        fn -> add_edge(source, second_target) end,
        self()
      )

    assert_receive :holding, 5_000

    deleter = start_write(scratch_opts, fn -> DB.delete(Module3, source.id) end)
    wait_for_blocked_sessions(scratch_opts, 1)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    assert Task.await(deleter) == :ok

    assert route(scratch, fn -> EntityOperations.get(Module3, source.id) end) == nil
    assert edge_target_ids(scratch, source) == []

    deleted_edges =
      [first_target.id, second_target.id]
      |> Enum.sort()
      |> Enum.map(&{"del_relationship", source.id, &1})

    expected_entries =
      Enum.concat([
        [{"add_relationship", source.id, second_target.id}],
        deleted_edges,
        [{"del_entity", source.id, nil}]
      ])

    assert scratch
           |> oplog_entries()
           |> Enum.drop(length(entries_before)) == expected_entries
  end

  test "an edge added from the row after the delete locked it fails", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    source = create_source(scratch)
    [first_target, second_target] = [create_target(scratch), create_target(scratch)]

    route(scratch, fn -> add_edge(source, first_target) end)

    entries_before = oplog_entries(scratch)

    # The holder locks the row's edge, so the delete parks on its edges, past its lock on the row.
    lock_edge = fn ->
      statement =
        ~s|SELECT 1 FROM #{qualified_join_table()} WHERE "source_id" = $1 FOR UPDATE|

      {:ok, %Postgrex.Result{num_rows: 1}} =
        Connection.query(statement, [Codec.encode(source.id, :uuid)])
    end

    holder = start_holder(scratch_opts, lock_edge, fn -> :ok end, self())
    assert_receive :holding, 5_000

    deleter = start_write(scratch_opts, fn -> DB.delete(Module3, source.id) end)
    wait_for_blocked_sessions(scratch_opts, 1)

    adder = start_write(scratch_opts, fn -> add_edge(source, second_target) end)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    assert Task.await(deleter) == :ok

    source_key = "#{join_table()}_source_id_$fk"

    assert %Postgrex.Error{
             postgres: %{code: :foreign_key_violation, constraint: ^source_key}
           } = Task.await(adder)

    assert route(scratch, fn -> EntityOperations.get(Module3, source.id) end) == nil
    assert edge_target_ids(scratch, source) == []

    assert scratch
           |> oplog_entries()
           |> Enum.drop(length(entries_before)) == [
             {"del_relationship", source.id, first_target.id},
             {"del_entity", source.id, nil}
           ]
  end
end
