defmodule Hologram.AuthContentionTest do
  # A gate reads the acting user's grant rows, and the write that follows trusts what it read.
  # Under read committed a revocation of one of those rows can commit between the two, and the
  # write lands on authority that is no longer there. What closes that is the gate share-locking
  # the rows it reads for the rest of its transaction, and the verb running gate and write in one:
  # the revocation's own row lock then waits for the gated write to commit, and lands after it.
  #
  # Neither half of that shows under the sandboxed case, where every test is one never-committed
  # transaction on one connection - so these tests live in the scratch tier, with a database of
  # their own and a real session per actor. The gated write is parked BETWEEN its gate and its
  # write by a third session holding the row the write is about to reach for, which is the only
  # place the answer the gate read has to keep. A revoker parked on the gate's rows and one that
  # has not got there yet look the same to a task that has not returned, so the wait is asserted
  # where it is visible: Postgres itself.
  #
  # async: false - the tier's modules run one at a time, since each opens raw sessions beside its
  # scratch connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Auth

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1

  defp create_user(scratch, email) do
    route(scratch, fn ->
      %{email: email}
      |> Module14.new()
      |> DB.create!()
    end)
  end

  defp hold_write(write, test_pid) do
    fn ->
      write.()

      send(test_pid, :holding)

      receive do
        :release -> :ok
      end
    end
  end

  defp on_own_session(scratch_opts, fun) do
    {:ok, session} = Postgrex.start_link(scratch_opts)

    route(session, fun)
  end

  # The users holding :owner on the resource, by id, sorted.
  defp owner_ids(scratch, resource) do
    statement = """
    SELECT "user_id" FROM "hologram_data"."hologram_role_grant"
    WHERE "entity_id" = $1 AND "role" = 'owner'
    """

    {:ok, %Postgrex.Result{rows: rows}} =
      route(scratch, fn -> Connection.query(statement, [Codec.encode(resource.id, :uuid)]) end)

    rows
    |> Enum.map(fn [user_id] -> Codec.decode(user_id, :uuid) end)
    |> Enum.sort()
  end

  # The gated write under the acting user, on a session of its own and with no transaction but the
  # verb's - what is under test is the verb holding its gate's rows until its write lands.
  defp start_gated_write(scratch_opts, actor, write) do
    Task.async(fn ->
      on_own_session(scratch_opts, fn -> Context.with_actor(actor.id, write) end)
    end)
  end

  # Trusted code holding a write of its own open until the test lets it commit: the same row the
  # gated write reaches for, so that the gated write parks between its gate and its write.
  defp start_holder(scratch_opts, write, test_pid) do
    Task.async(fn ->
      on_own_session(scratch_opts, fn -> Connection.transaction(hold_write(write, test_pid)) end)
    end)
  end

  # Trusted code taking the acting user's :owner away - no gate of its own, straight to the row
  # the gated write's gate rests on.
  defp start_revoker(scratch_opts, actor, resource) do
    Task.async(fn ->
      on_own_session(scratch_opts, fn -> revoke_role(actor, resource, :owner) end)
    end)
  end

  # Scoped to this database and excluding the observer, because pg_stat_activity is the whole
  # server: the rest of the suite runs against another database at the same moment.
  defp wait_for_blocked_sessions(scratch_opts, count) do
    {:ok, observer} = Postgrex.start_link(scratch_opts)

    statement = """
    SELECT count(*) FROM pg_catalog.pg_stat_activity
    WHERE "datname" = current_database() AND "wait_event_type" = 'Lock'
      AND "pid" <> pg_backend_pid()
    """

    wait_until(fn ->
      %Postgrex.Result{rows: [[blocked]]} = Postgrex.query!(observer, statement, [])

      blocked == count
    end)
  end

  setup %{scratch: scratch} do
    # A virgin database claims itself and converges to the whole model, so the user, resource and
    # grant tables exist.
    route(scratch, fn -> SchemaReconciler.reconcile(DB.reconciliation_context()) end)

    alice = create_user(scratch, "alice@example.com")
    bob = create_user(scratch, "bob@example.com")
    resource = route(scratch, fn -> DB.create!(Module1.new()) end)

    route(scratch, fn -> grant_role(alice, resource, :owner) end)

    [alice: alice, bob: bob, resource: resource]
  end

  test "a grant holds the rows its gate read until its write lands", %{
    alice: alice,
    bob: bob,
    resource: resource,
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    # The holder's uncommitted row is the one the gated grant derives the same id for, so the
    # gated insert waits on it - parked past its gate, before its write.
    grant = fn -> grant_role(bob, resource, :owner) end
    holder = start_holder(scratch_opts, grant, self())
    assert_receive :holding, 5_000

    gated = start_gated_write(scratch_opts, alice, grant)
    wait_for_blocked_sessions(scratch_opts, 1)

    # The revocation of alice's :owner queues behind the gate's hold on that row.
    revoker = start_revoker(scratch_opts, alice, resource)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    assert Task.await(gated) == :ok
    assert Task.await(revoker) == :ok

    assert owner_ids(scratch, resource) == [bob.id]
  end

  test "a revocation holds the rows its gate read until its write lands", %{
    alice: alice,
    bob: bob,
    resource: resource,
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    route(scratch, fn -> grant_role(bob, resource, :owner) end)

    # The holder's uncommitted deletion is of the row the gated revocation locks next, so the
    # gated revocation waits on it - parked past its gate, before its write.
    revoke = fn -> revoke_role(bob, resource, :owner) end
    holder = start_holder(scratch_opts, revoke, self())
    assert_receive :holding, 5_000

    gated = start_gated_write(scratch_opts, alice, revoke)
    wait_for_blocked_sessions(scratch_opts, 1)

    # The revocation of alice's :owner queues behind the gate's hold on that row.
    revoker = start_revoker(scratch_opts, alice, resource)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    assert Task.await(gated) == :ok
    assert Task.await(revoker) == :ok

    assert owner_ids(scratch, resource) == []
  end
end
