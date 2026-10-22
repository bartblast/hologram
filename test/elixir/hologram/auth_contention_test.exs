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
  # Every other write under an acting user reads the grants its policy rests on through the same
  # hold, wherever the policy reads them - a role on the row, on its whole type, or on a related
  # row - and a create evaluates inside the transaction its insert runs in. Such a write is parked
  # on the parent row it names: a third session holds that row FOR UPDATE, and the write's foreign
  # key check, which share-locks the row it references, waits there - past the evaluation, before
  # the write.
  #
  # A delegated write reads the related row its `via:` rule hands the question to, and holds that
  # row the same way, every hop of a chain - a trusted change to it waits for the write to commit.
  # Such a write is parked the same way, on a foreign key check: its update moves the row to a
  # second parent a third session holds, so the evaluation ran against the row as it stood, with
  # the parent it read and holds.
  #
  # async: false - the tier's modules run one at a time, since each opens raw sessions beside its
  # scratch connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Auth
  import Hologram.Query, only: [authorize: 2, put_attribute: 3]

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module2
  alias Hologram.Test.Fixtures.Policy.Module5
  alias Hologram.Test.Fixtures.Policy.Module8

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

  # Trusted code changing a related row a delegation read - no gate of its own, straight to the row
  # the gated write's evaluation rests on.
  defp start_changer(scratch_opts, entity, attribute, value) do
    Task.async(fn ->
      on_own_session(scratch_opts, fn ->
        entity
        |> put_attribute(attribute, value)
        |> DB.update()
      end)
    end)
  end

  # The gated write under the acting user, on a session of its own and with no transaction but the
  # verb's - what is under test is the verb holding what its evaluation read, the grant rows and
  # the related rows its delegations read, until its write lands.
  defp start_gated_write(scratch_opts, actor, write) do
    Task.async(fn ->
      on_own_session(scratch_opts, fn -> Context.with_actor(actor.id, write) end)
    end)
  end

  # Trusted code holding a transaction of its own open until the test lets it commit, on a row the
  # gated write reaches for - so that the gated write parks past its evaluation, before its write.
  defp start_holder(scratch_opts, write, test_pid) do
    Task.async(fn ->
      on_own_session(scratch_opts, fn -> Connection.transaction(hold_write(write, test_pid)) end)
    end)
  end

  # Trusted code taking a role of the acting user's away - no gate of its own, straight to the row
  # the gated write's evaluation rests on.
  defp start_revoker(scratch_opts, actor, role, entity) do
    Task.async(fn ->
      on_own_session(scratch_opts, fn -> revoke_role(actor, role, entity) end)
    end)
  end

  # A third session holding a row FOR UPDATE, so that a write naming it parks on its foreign key
  # check - after its evaluation, before its row lands.
  defp start_row_holder(scratch_opts, row, test_pid) do
    lock = fn -> EntityOperations.get(row.__struct__, row.id, lock: :update) end

    start_holder(scratch_opts, lock, test_pid)
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
    # Priority 5 is what lets alice's :owner, which extends :editor, update it.
    resource =
      route(scratch, fn ->
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()
      end)

    route(scratch, fn -> grant_role(alice, :owner, resource) end)

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
    grant = fn -> grant_role(bob, :owner, resource) end
    holder = start_holder(scratch_opts, grant, self())
    assert_receive :holding, 5_000

    gated = start_gated_write(scratch_opts, alice, grant)
    wait_for_blocked_sessions(scratch_opts, 1)

    # The revocation of alice's :owner queues behind the gate's hold on that row.
    revoker = start_revoker(scratch_opts, alice, :owner, resource)
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
    route(scratch, fn -> grant_role(bob, :owner, resource) end)

    # The holder's uncommitted deletion is of the row the gated revocation locks next, so the
    # gated revocation waits on it - parked past its gate, before its write.
    revoke = fn -> revoke_role(bob, :owner, resource) end
    holder = start_holder(scratch_opts, revoke, self())
    assert_receive :holding, 5_000

    gated = start_gated_write(scratch_opts, alice, revoke)
    wait_for_blocked_sessions(scratch_opts, 1)

    # The revocation of alice's :owner queues behind the gate's hold on that row.
    revoker = start_revoker(scratch_opts, alice, :owner, resource)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    assert Task.await(gated) == :ok
    assert Task.await(revoker) == :ok

    assert owner_ids(scratch, resource) == []
  end

  test "a create holds the grant rows its evaluation read until its row lands", %{
    alice: alice,
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    route(scratch, fn -> grant_role(alice, :editor, Module1) end)
    parent = route(scratch, fn -> DB.create!(Module2.new()) end)

    entity =
      %{parent_id: parent.id, priority: 5}
      |> Module1.new()
      |> authorize(:update)

    holder = start_row_holder(scratch_opts, parent, self())
    assert_receive :holding, 5_000

    gated = start_gated_write(scratch_opts, alice, fn -> DB.create(entity) end)
    wait_for_blocked_sessions(scratch_opts, 1)

    # The revocation of alice's type-wide :editor queues behind the evaluation's hold on that row.
    revoker = start_revoker(scratch_opts, alice, :editor, Module1)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    entity_id = entity.id
    assert {:ok, %Module1{id: ^entity_id}} = Task.await(gated)
    assert Task.await(revoker) == :ok

    assert route(scratch, fn -> DB.read(Module1, entity.id) end).parent_id == parent.id
    refute route(scratch, fn -> has_role?(alice, :editor, Module1) end)
  end

  test "an update holds the grant rows its evaluation read until its write lands", %{
    alice: alice,
    resource: resource,
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    parent = route(scratch, fn -> DB.create!(Module2.new()) end)

    holder = start_row_holder(scratch_opts, parent, self())
    assert_receive :holding, 5_000

    update = fn ->
      resource
      |> put_attribute(:parent_id, parent.id)
      |> DB.update()
    end

    gated = start_gated_write(scratch_opts, alice, update)
    wait_for_blocked_sessions(scratch_opts, 1)

    # The revocation of alice's :owner queues behind the evaluation's hold on that row.
    revoker = start_revoker(scratch_opts, alice, :owner, resource)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    assert Task.await(gated) == :ok
    assert Task.await(revoker) == :ok

    assert route(scratch, fn -> DB.read(Module1, resource.id) end).parent_id == parent.id
    assert owner_ids(scratch, resource) == []
  end

  test "a write holds the grant rows it read on a related row", %{
    alice: alice,
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    parent = route(scratch, fn -> DB.create!(Module2.new()) end)
    route(scratch, fn -> grant_role(alice, :admin, parent) end)

    # Module1's :delete is granted by :admin on the PARENT row - a grant on another resource,
    # which no gate reads.
    entity =
      %{parent_id: parent.id, priority: 5}
      |> Module1.new()
      |> authorize(:delete)

    holder = start_row_holder(scratch_opts, parent, self())
    assert_receive :holding, 5_000

    gated = start_gated_write(scratch_opts, alice, fn -> DB.create(entity) end)
    wait_for_blocked_sessions(scratch_opts, 1)

    # The revocation of alice's :admin on the parent queues behind the evaluation's hold on it.
    revoker = start_revoker(scratch_opts, alice, :admin, parent)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    entity_id = entity.id
    assert {:ok, %Module1{id: ^entity_id}} = Task.await(gated)
    assert Task.await(revoker) == :ok

    assert route(scratch, fn -> DB.read(Module1, entity.id) end).parent_id == parent.id
    refute route(scratch, fn -> has_role?(alice, :admin, parent) end)
  end

  test "an update holds the related row its delegation read until its write lands", %{
    alice: alice,
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    old_parent =
      route(scratch, fn ->
        %{public: true}
        |> Module2.new()
        |> DB.create!()
      end)

    new_parent = route(scratch, fn -> DB.create!(Module2.new()) end)

    # Module1's :publish is `via: parent`, and Module2's :publish holds while the parent is public -
    # so alice may publish the row while its old parent stays public, with no role of her own.
    entity =
      route(scratch, fn ->
        %{parent_id: old_parent.id}
        |> Module1.new()
        |> DB.create!()
      end)

    holder = start_row_holder(scratch_opts, new_parent, self())
    assert_receive :holding, 5_000

    update = fn ->
      entity
      |> put_attribute(:parent_id, new_parent.id)
      |> authorize(:publish)
      |> DB.update()
    end

    gated = start_gated_write(scratch_opts, alice, update)
    wait_for_blocked_sessions(scratch_opts, 1)

    # The change to the old parent queues behind the evaluation's hold on it.
    changer = start_changer(scratch_opts, old_parent, :public, false)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    assert Task.await(gated) == :ok
    assert Task.await(changer) == :ok

    assert route(scratch, fn -> DB.read(Module1, entity.id) end).parent_id == new_parent.id
    assert route(scratch, fn -> DB.read(Module2, old_parent.id) end).public == false
  end

  test "an update holds the far row of a delegation chain until its write lands", %{
    alice: alice,
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    # Module8's :read is `via: parent` at Module5, whose :read is `via: parent` at Module1, whose
    # :read holds while the row is public - so alice may read the row through both hops.
    chain_end =
      route(scratch, fn ->
        %{public: true}
        |> Module1.new()
        |> DB.create!()
      end)

    old_middle =
      route(scratch, fn ->
        %{parent_id: chain_end.id}
        |> Module5.new()
        |> DB.create!()
      end)

    new_middle = route(scratch, fn -> DB.create!(Module5.new()) end)

    entity =
      route(scratch, fn ->
        %{parent_id: old_middle.id}
        |> Module8.new()
        |> DB.create!()
      end)

    holder = start_row_holder(scratch_opts, new_middle, self())
    assert_receive :holding, 5_000

    update = fn ->
      entity
      |> put_attribute(:parent_id, new_middle.id)
      |> authorize(:read)
      |> DB.update()
    end

    gated = start_gated_write(scratch_opts, alice, update)
    wait_for_blocked_sessions(scratch_opts, 1)

    # The change to the row at the END of the chain queues behind the evaluation's hold on it.
    changer = start_changer(scratch_opts, chain_end, :public, false)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    assert Task.await(gated) == :ok
    assert Task.await(changer) == :ok

    assert route(scratch, fn -> DB.read(Module8, entity.id) end).parent_id == new_middle.id
    assert route(scratch, fn -> DB.read(Module1, chain_end.id) end).public == false
  end
end
