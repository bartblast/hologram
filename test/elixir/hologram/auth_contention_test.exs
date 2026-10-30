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
  # Two such holds can cross another transaction's locks, and PostgreSQL then aborts one of the two
  # as a deadlock victim. A third session parks both sides so that, when it lets go, each holds what
  # the other waits for. PostgreSQL aborts the session whose deadlock check finds the cycle first, so
  # the session under test is elected the victim through a shorter deadlock_timeout - and its verb,
  # run again, answers the way it would have a moment later.
  #
  # async: false - the tier's modules run one at a time, since each opens raw sessions beside its
  # scratch connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Auth
  import Hologram.Query, only: [authorize: 2, put_attribute: 3]

  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Mutation
  alias Hologram.Runtime.Serializer
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module2
  alias Hologram.Test.Fixtures.Policy.Module5
  alias Hologram.Test.Fixtures.Policy.Module8

  # A browser's batch carrying the given writes, as the wire carries it.
  defp batch(writes) do
    %{
      "instance_id" => "i1",
      "model_hash" => Model.hash(),
      "replica_id" => Entity.generate_id(),
      "seq" => 1,
      "writes" => writes
    }
  end

  defp create_user(scratch, email) do
    route(scratch, fn ->
      %{email: email}
      |> Module14.new()
      |> DB.create!()
    end)
  end

  # A gated write crossing a batch that revokes its actor's role. The gated write under alice parks
  # on its FOR UPDATE of the resource, which a holder shares. Bob's batch revokes alice's :owner,
  # locking her grant row, and parks on the resource behind the gated write - PostgreSQL hands the
  # row to the first in its queue, so the gated write has to park first, or the batch would simply
  # land before it. When the holder lets go, the gated write takes the resource and asks for its
  # grant row, and the batch wakes and asks for the resource: each holds what the other waits for.
  # The gated write's session is the elected victim, and run again it finds alice's role gone.
  # Returns the gated write's answer and the batch's.
  defp cross_with_revoking_batch(context, write) do
    %{alice: alice, bob: bob, resource: resource, scratch: scratch, scratch_opts: scratch_opts} =
      context

    route(scratch, fn -> grant_role(bob, :owner, resource) end)

    alice_grant_id = RoleGrant.derive_id(alice.id, Module1, resource.id, :owner)
    alice_grant = route(scratch, fn -> EntityOperations.get(RoleGrant, alice_grant_id) end)

    holder = start_share_holder(scratch_opts, resource, self())
    assert_receive :holding, 5_000

    gated = start_victim(scratch_opts, alice, fn -> refusal_or_result(write) end)
    wait_for_blocked_sessions(scratch_opts, 1)

    writes = [
      revocation_write(alice.id, :owner, resource, alice_grant),
      update_write(resource, %{"priority" => 9})
    ]

    by_bob = start_batch(scratch_opts, bob, batch(writes))
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    {Task.await(gated), Task.await(by_bob)}
  end

  # Makes the calling process's session the one PostgreSQL aborts should it end up in a deadlock.
  # PostgreSQL aborts the process whose deadlock check finds the cycle, and a process checks once,
  # deadlock_timeout after it starts waiting - so the session with the shortest timeout is the
  # victim whenever the other side is waiting by then, which in every staging here it is within a
  # millisecond. A superuser's setting, which the test user is.
  defp elect_victim do
    {:ok, _result} = Connection.query("SET deadlock_timeout = '100ms'")

    :ok
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

  # The refusal a gated write raises, returned as a value - a task that raised would take the test
  # down with it.
  defp refusal_or_result(fun) do
    fun.()
  rescue
    error in Hologram.AccessDeniedError -> error
  end

  # A browser's revocation of the given user's role on the resource, as the wire carries it: based
  # on the grant row as it stands.
  defp revocation_write(user_id, role, resource, row) do
    %{
      "based_on" => stringify_keys(row.__meta__.revisions),
      "claim" => nil,
      "data" => %{
        "entity_id" => resource.id,
        "entity_type" => Codec.encode_enum_value(resource.__struct__),
        "role" => Atom.to_string(role),
        "user_id" => user_id
      },
      "id" => row.id,
      "op" => "delete",
      "stamp" => stamp_above(row),
      "type" => inspect(RoleGrant)
    }
  end

  # A stamp above every revision the row holds - the applier refuses a stamp that is not above the
  # revisions its write was based on, and a row written this millisecond can already carry one above
  # the raw wall clock.
  defp stamp_above(row) do
    highest_revision =
      row.__meta__.revisions
      |> Map.values()
      |> Enum.max()

    max(System.os_time(:millisecond) * 1024, highest_revision + 1)
  end

  # A batch applied on a session of its own under the given user, as a request applies it.
  defp start_batch(scratch_opts, actor, batch) do
    Task.async(fn ->
      on_own_session(scratch_opts, fn -> Mutation.run(batch, %Server{user_id: actor.id}) end)
    end)
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

  # A third session holding grant rows FOR SHARE: a gate's own share lock passes it and a
  # revocation's FOR UPDATE parks on it, so a gated revocation parks past its gate, before its
  # write - and two of them have both run their gates when the holder lets go.
  defp start_grant_share_holder(scratch_opts, grant_ids, test_pid) do
    lock = fn -> Enum.each(grant_ids, &EntityOperations.get(RoleGrant, &1, lock: :share)) end

    start_holder(scratch_opts, lock, test_pid)
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

  # A third session holding a row FOR SHARE: a write's FOR UPDATE of it parks there, while the
  # rows around it stay free for whoever comes next.
  defp start_share_holder(scratch_opts, row, test_pid) do
    lock = fn -> EntityOperations.get(row.__struct__, row.id, lock: :share) end

    start_holder(scratch_opts, lock, test_pid)
  end

  # The write under test, on a session of its own elected as the deadlock victim - under the given
  # actor, or trusted code with nil.
  defp start_victim(scratch_opts, actor, write) do
    actor_id = actor && actor.id

    Task.async(fn ->
      on_own_session(scratch_opts, fn ->
        elect_victim()

        Context.with_actor(actor_id, write)
      end)
    end)
  end

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)

  # A browser's update of the given row, as the wire carries it: based on the stored revision of
  # each field it writes.
  defp update_write(row, values) do
    names =
      values
      |> Map.keys()
      |> Enum.map(&String.to_existing_atom/1)

    based_on =
      row.__meta__.revisions
      |> Map.take(names)
      |> stringify_keys()

    %{
      "based_on" => based_on,
      "claim" => nil,
      "data" => values,
      "id" => row.id,
      "op" => "update",
      "stamp" => stamp_above(row),
      "type" => inspect(row.__struct__)
    }
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

  test "two users revoking each other's role at the same moment land one revocation and refuse the other",
       %{
         alice: alice,
         bob: bob,
         resource: resource,
         scratch: scratch,
         scratch_opts: scratch_opts
       } do
    route(scratch, fn -> grant_role(bob, :owner, resource) end)

    grant_ids =
      Enum.map([alice, bob], &RoleGrant.derive_id(&1.id, Module1, resource.id, :owner))

    holder = start_grant_share_holder(scratch_opts, grant_ids, self())
    assert_receive :holding, 5_000

    revoke = fn user -> refusal_or_result(fn -> revoke_role(user, :owner, resource) end) end

    by_alice = start_gated_write(scratch_opts, alice, fn -> revoke.(bob) end)
    by_bob = start_gated_write(scratch_opts, bob, fn -> revoke.(alice) end)
    wait_for_blocked_sessions(scratch_opts, 2)

    # When the holder lets go, each revocation's FOR UPDATE waits on the other's gate. PostgreSQL
    # finds the cycle after its deadlock_timeout, a second by default, and aborts one of the two -
    # rerun, that one finds its actor's role gone.
    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    refused = %Hologram.AccessDeniedError{
      message:
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)} that may revoke :owner"
    }

    results = {Task.await(by_alice), Task.await(by_bob)}
    assert results in [{:ok, refused}, {refused, :ok}]

    winner = if results == {:ok, refused}, do: alice, else: bob
    assert owner_ids(scratch, resource) == [winner.id]
  end

  test "two batches revoking each other's role at the same moment land one revocation and refuse the other",
       %{
         alice: alice,
         bob: bob,
         resource: resource,
         scratch: scratch,
         scratch_opts: scratch_opts
       } do
    route(scratch, fn -> grant_role(bob, :owner, resource) end)

    [alice_row, bob_row] =
      Enum.map([alice, bob], fn user ->
        grant_id = RoleGrant.derive_id(user.id, Module1, resource.id, :owner)

        route(scratch, fn -> EntityOperations.get(RoleGrant, grant_id) end)
      end)

    holder = start_grant_share_holder(scratch_opts, [alice_row.id, bob_row.id], self())
    assert_receive :holding, 5_000

    by_alice =
      start_batch(
        scratch_opts,
        alice,
        batch([revocation_write(bob.id, :owner, resource, bob_row)])
      )

    by_bob =
      start_batch(
        scratch_opts,
        bob,
        batch([revocation_write(alice.id, :owner, resource, alice_row)])
      )

    wait_for_blocked_sessions(scratch_opts, 2)

    # The verbs' cycle, in the batches: each one's FOR UPDATE on the row it revokes waits on the
    # other's gate once the holder lets go, and the one PostgreSQL aborts is applied again.
    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    confirmed = {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

    message =
      "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)} that may revoke :owner"

    rejected =
      {:ok,
       %{
         "reason" => Serializer.serialize!(%Hologram.AccessDeniedError{message: message}),
         "status" => "rejected",
         "write" => 0
       }}

    results = {Task.await(by_alice), Task.await(by_bob)}
    assert results in [{confirmed, rejected}, {rejected, confirmed}]

    winner = if results == {confirmed, rejected}, do: alice, else: bob
    assert owner_ids(scratch, resource) == [winner.id]
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

  test "an update aborted as a deadlock victim is run again and refused once its actor's role is gone",
       %{resource: resource, scratch: scratch} = context do
    update = fn ->
      resource
      |> put_attribute(:priority, 7)
      |> DB.update()
    end

    assert cross_with_revoking_batch(context, update) == {
             %Hologram.AccessDeniedError{
               message:
                 "not allowed to update Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}"
             },
             {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}
           }

    assert route(scratch, fn -> DB.read(Module1, resource.id) end).priority == 9
    assert owner_ids(scratch, resource) == [context.bob.id]
  end

  test "a type-indexed update aborted as a deadlock victim is run again and refused once its actor's role is gone",
       %{resource: resource, scratch: scratch} = context do
    update = fn -> DB.update(Module1, resource.id, priority: 7) end

    assert cross_with_revoking_batch(context, update) == {
             %Hologram.AccessDeniedError{
               message:
                 "not allowed to update Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}"
             },
             {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}
           }

    assert route(scratch, fn -> DB.read(Module1, resource.id) end).priority == 9
    assert owner_ids(scratch, resource) == [context.bob.id]
  end

  test "a delete aborted as a deadlock victim is run again and refused once its actor's role is gone",
       %{resource: resource, scratch: scratch} = context do
    # The delete claims the :update rule, which alice's :owner grants on the row itself - Module1's
    # own :delete rests on a role on its parent, which this cycle has no use for.
    delete = fn ->
      resource
      |> authorize(:update)
      |> DB.delete()
    end

    assert cross_with_revoking_batch(context, delete) == {
             %Hologram.AccessDeniedError{
               message:
                 "not allowed to update Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}"
             },
             {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}
           }

    assert route(scratch, fn -> DB.read(Module1, resource.id) end).priority == 9
    assert owner_ids(scratch, resource) == [context.bob.id]
  end

  test "a create aborted as a deadlock victim is run again and refused once its actor's role is gone",
       %{
         alice: alice,
         bob: bob,
         scratch: scratch,
         scratch_opts: scratch_opts
       } do
    parent = route(scratch, fn -> DB.create!(Module2.new()) end)
    route(scratch, fn -> grant_role(alice, :admin, parent) end)
    route(scratch, fn -> grant_role(bob, :admin, parent) end)

    alice_grant_id = RoleGrant.derive_id(alice.id, Module2, parent.id, :admin)
    alice_grant = route(scratch, fn -> EntityOperations.get(RoleGrant, alice_grant_id) end)

    # Module1's :delete is granted by :admin on the parent row, a grant a batch can revoke.
    entity =
      %{parent_id: parent.id, priority: 5}
      |> Module1.new()
      |> authorize(:delete)

    # A create's first lock is its evaluation's share lock on alice's grant row, and its second the
    # foreign key check's on the parent. The batch takes them the other way round: it updates the
    # parent, then revokes alice's :admin on it. With the holder on the grant row, the create parks
    # on its evaluation first and the batch's revocation queues behind it, its parent already
    # locked. When the holder lets go the create evaluates, inserts and waits on the parent, and the
    # batch waits on the create's share lock.
    holder = start_row_holder(scratch_opts, alice_grant, self())
    assert_receive :holding, 5_000

    gated =
      start_victim(scratch_opts, alice, fn -> refusal_or_result(fn -> DB.create(entity) end) end)

    wait_for_blocked_sessions(scratch_opts, 1)

    writes = [
      update_write(parent, %{"public" => true}),
      revocation_write(alice.id, :admin, parent, alice_grant)
    ]

    by_bob = start_batch(scratch_opts, bob, batch(writes))
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    assert Task.await(gated) == %Hologram.AccessDeniedError{
             message:
               "not allowed to delete Hologram.Test.Fixtures.Policy.Module1 #{inspect(entity.id)}"
           }

    assert Task.await(by_bob) ==
             {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

    assert route(scratch, fn -> DB.read(Module1, entity.id) end) == nil
    assert route(scratch, fn -> DB.read(Module2, parent.id) end).public == true
    refute route(scratch, fn -> has_role?(alice, :admin, parent) end)
  end

  test "a trusted delete aborted as a deadlock victim is run again and answers the reference that restricts it",
       %{
         alice: alice,
         scratch: scratch,
         scratch_opts: scratch_opts
       } do
    parent =
      route(scratch, fn ->
        %{public: true}
        |> Module2.new()
        |> DB.create!()
      end)

    entity =
      route(scratch, fn ->
        %{parent_id: parent.id}
        |> Module1.new()
        |> DB.create!()
      end)

    # Module1's :publish is `via: parent`, and Module2's :publish holds while the parent is public -
    # so alice may publish the row with no role of her own, reading the parent FOR SHARE.
    update = fn ->
      entity
      |> put_attribute(:priority, 7)
      |> authorize(:publish)
      |> DB.update()
    end

    # The delegated update locks the row, then reads the parent. The delete takes the parent, then
    # its foreign key check asks for the row referencing it. With the holder on the row, the update
    # parks on it first and the delete's foreign key check queues behind it, the parent already
    # taken. When the holder lets go the update takes the row and waits on the parent, and the
    # delete waits on the row.
    holder = start_row_holder(scratch_opts, entity, self())
    assert_receive :holding, 5_000

    gated = start_gated_write(scratch_opts, alice, update)
    wait_for_blocked_sessions(scratch_opts, 1)

    trusted = start_victim(scratch_opts, nil, fn -> DB.delete(Module2, parent.id) end)
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    assert Task.await(gated) == :ok
    assert Task.await(trusted) == {:error, %{referenced_by: Module1, relationship: :parent}}

    assert route(scratch, fn -> DB.read(Module1, entity.id) end).priority == 7
    assert route(scratch, fn -> DB.read(Module2, parent.id) end).public == true
  end

  test "a trusted type-indexed update aborted as a deadlock victim is run again and lands", %{
    alice: alice,
    resource: resource,
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    parent = route(scratch, fn -> DB.create!(Module2.new()) end)
    route(scratch, fn -> grant_role(alice, :admin, parent) end)

    # The trusted update locks the row, then its foreign key check asks for the parent it moves the
    # row to. Alice's batch takes them the other way round: it updates the parent, then the row.
    # With the holder on the row, the trusted update parks on it first and the batch queues behind
    # it, the parent already locked. When the holder lets go the trusted update takes the row and
    # waits on the parent, and the batch waits on the row.
    holder = start_row_holder(scratch_opts, resource, self())
    assert_receive :holding, 5_000

    trusted =
      start_victim(scratch_opts, nil, fn ->
        DB.update(Module1, resource.id, parent_id: parent.id)
      end)

    wait_for_blocked_sessions(scratch_opts, 1)

    writes = [
      update_write(parent, %{"public" => true}),
      update_write(resource, %{"priority" => 9})
    ]

    by_alice = start_batch(scratch_opts, alice, batch(writes))
    wait_for_blocked_sessions(scratch_opts, 2)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)

    assert Task.await(trusted) == :ok

    assert Task.await(by_alice) ==
             {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

    stored = route(scratch, fn -> DB.read(Module1, resource.id) end)
    assert {stored.parent_id, stored.priority} == {parent.id, 9}
    assert route(scratch, fn -> DB.read(Module2, parent.id) end).public == true
  end
end
