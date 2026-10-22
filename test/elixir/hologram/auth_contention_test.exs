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
  alias Hologram.Auth.RoleGrant
  alias Hologram.Compiler.Encoder
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Mutation
  alias Hologram.Server
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

  # The refusal a gated write raises, returned as a value - a task that raised would take the test
  # down with it.
  defp refusal_or_result(fun) do
    fun.()
  rescue
    error in Hologram.AccessDeniedError -> error
  end

  # A browser's revocation of the given user's :owner on the resource, as the wire carries it: one
  # write, based on the grant row as it stands, stamped above every revision it holds - the applier
  # refuses a stamp that is not above the revisions its write was based on, and a row written this
  # millisecond can already carry one above the raw wall clock.
  defp revocation_batch(user_id, resource, row) do
    revisions =
      Map.new(row.__meta__.revisions, fn {name, revision} ->
        {Atom.to_string(name), revision}
      end)

    highest_revision =
      row.__meta__.revisions
      |> Map.values()
      |> Enum.max()

    write = %{
      "based_on" => revisions,
      "claim" => nil,
      "data" => %{
        "entity_id" => resource.id,
        "entity_type" => Codec.encode_enum_value(resource.__struct__),
        "role" => "owner",
        "user_id" => user_id
      },
      "id" => row.id,
      "op" => "delete",
      "stamp" => max(System.os_time(:millisecond) * 1024, highest_revision + 1),
      "type" => inspect(RoleGrant)
    }

    %{
      "instance_id" => "i1",
      "model_hash" => Model.hash(),
      "replica_id" => Entity.generate_id(),
      "seq" => 1,
      "writes" => [write]
    }
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

    by_alice = start_batch(scratch_opts, alice, revocation_batch(bob.id, resource, bob_row))
    by_bob = start_batch(scratch_opts, bob, revocation_batch(alice.id, resource, alice_row))
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
         "reason" => Encoder.encode_client_term!(%Hologram.AccessDeniedError{message: message}),
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
end
