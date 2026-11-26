defmodule Hologram.DB.WriterTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.Writer

  import Hologram.Query,
    only: [
      add_relationship: 3,
      decrement: 3,
      delete_relationship: 3,
      increment: 3,
      put_attribute: 3,
      trust: 1
    ]

  import Hologram.Test, only: [as_user: 2]

  alias Hologram.AccessDeniedError
  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Job
  alias Hologram.MisuseError
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module16
  alias Hologram.Test.Fixtures.Entity.Module20
  alias Hologram.Test.Fixtures.Job.Module1, as: JobModule1
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module10, as: PolicyModule10
  alias Hologram.Test.Fixtures.Policy.Module11, as: PolicyModule11
  alias Hologram.Test.Fixtures.Policy.Module2
  alias Hologram.Test.Fixtures.Policy.Module26
  alias Hologram.Test.Fixtures.Policy.Module36
  alias Hologram.Test.Fixtures.Policy.Module38, as: Channel
  alias Hologram.Test.Fixtures.Policy.Module39, as: ChannelMessage
  alias Hologram.Test.Fixtures.Policy.Module40
  alias Hologram.Test.Fixtures.Policy.Module58, as: ChangedProject
  alias Hologram.Test.Fixtures.Policy.Module59, as: ChangedTask
  alias Hologram.Test.Fixtures.Policy.Module60, as: ChangedLabel
  alias Hologram.Test.Fixtures.Policy.Module9

  defp create_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  defp with_past_updated_at(%entity_type{id: id}) do
    table = Map.fetch!(DB.mapping(), entity_type).table

    {:ok, _result} =
      Connection.query(
        ~s|UPDATE "hologram_data"."#{table}" SET "updated_at" = "updated_at" - interval '1 hour' | <>
          ~s|WHERE "id" = $1|,
        [Codec.encode(id, :uuid)]
      )

    EntityOperations.get(entity_type, id)
  end

  defp count_edges(source_entity, target_entity) do
    count_sql =
      ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module16_secrets_$join" | <>
        ~s|WHERE "source_id" = $1 AND "target_id" = $2|

    {:ok, %Postgrex.Result{rows: [[count]]}} =
      Connection.query(count_sql, [
        Codec.encode(source_entity.id, :uuid),
        Codec.encode(target_entity.id, :uuid)
      ])

    count
  end

  defp job_framework_values do
    [
      actor_id: nil,
      attempt: 0,
      error: "failed",
      run_as_server: false,
      scheduled_at: DateTime.utc_now(),
      status: :done
    ]
  end

  defp granted_roles(user_id, entity_id) do
    select_sql =
      ~s|SELECT "role" FROM "hologram_data"."hologram_role_grant" | <>
        ~s|WHERE "user_id" = $1 AND "entity_id" = $2 ORDER BY "role"|

    {:ok, %{rows: rows}} =
      Connection.query(select_sql, [
        Codec.encode(user_id, :uuid),
        Codec.encode(entity_id, :uuid)
      ])

    Enum.map(rows, fn [role] -> role end)
  end

  defp oplog_actor_ids(entity_id) do
    statement = ~s|SELECT "actor_id" FROM "hologram_system"."oplog" WHERE "entity_id" = $1|

    {:ok, %Postgrex.Result{rows: rows}} =
      Connection.query(statement, [Codec.encode(entity_id, :uuid)])

    Enum.map(rows, fn [actor_id] -> actor_id end)
  end

  defp last_old_references do
    statement = ~s|SELECT "old" FROM "hologram_system"."oplog" ORDER BY "seq" DESC LIMIT 1|

    {:ok, %Postgrex.Result{rows: [[old]]}} = Connection.query(statement)

    old
  end

  describe "a signed-out session" do
    test "is refused a create no rule gives a visitor" do
      entity = Module2.new(public: true)

      expected_msg =
        ~s(not allowed to create Hologram.Test.Fixtures.Policy.Module2 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(nil, fn -> create(entity) end)
      end

      assert DB.read(Module2, entity.id) == nil
    end

    test "creates what a rule gives a visitor" do
      entity = Module9.new()

      assert {:ok, %Module9{}} = as_user(nil, fn -> create(entity) end)
      assert DB.read(Module9, entity.id) != nil
    end

    test "is refused an update of a struct no rule gives a visitor" do
      entity =
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()

      changed = put_attribute(entity, :priority, 7)

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}" - no allow line that holds covers :priority)

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(nil, fn -> update(changed) end)
      end

      assert DB.read(Module1, entity.id).priority == 5
    end

    test "is refused an update by type and id no rule gives a visitor" do
      entity =
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}" - no allow line that holds covers :priority)

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(nil, fn -> update(Module1, entity.id, priority: 7) end)
      end

      assert DB.read(Module1, entity.id).priority == 5
    end

    test "updates what a rule gives a visitor" do
      entity = DB.create!(Module9.new())

      assert as_user(nil, fn -> update(Module9, entity.id, archived: true) end) == :ok
      assert DB.read(Module9, entity.id).archived == true
    end

    test "updates a struct a rule gives a visitor" do
      entity = DB.create!(Module9.new())
      changed = put_attribute(entity, :archived, true)

      assert as_user(nil, fn -> update(changed) end) == :ok
      assert DB.read(Module9, entity.id).archived == true
    end

    test "deletes a struct a rule gives a visitor" do
      entity = DB.create!(Module26.new())

      assert as_user(nil, fn -> delete(entity) end) == :ok
      assert DB.read(Module26, entity.id) == nil
    end

    test "deletes by type and id what a rule gives a visitor" do
      entity = DB.create!(Module26.new())

      assert as_user(nil, fn -> delete(Module26, entity.id) end) == :ok
      assert DB.read(Module26, entity.id) == nil
    end

    test "is refused a delete of a struct no rule gives a visitor" do
      entity = DB.create!(Module1.new())

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(nil, fn -> delete(entity) end)
      end

      assert DB.read(Module1, entity.id) != nil
    end

    test "is refused a delete by type and id no rule gives a visitor" do
      entity = DB.create!(Module1.new())

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(nil, fn -> delete(Module1, entity.id) end)
      end

      assert DB.read(Module1, entity.id) != nil
    end

    test "creates past the rules with a trust claim" do
      entity = Module2.new(public: true)

      trusted_entity = trust(entity)

      assert {:ok, %Module2{}} = as_user(nil, fn -> create(trusted_entity) end)
      assert DB.read(Module2, entity.id) != nil
    end

    test "updates past the rules with a trust claim" do
      entity =
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()

      result =
        as_user(nil, fn ->
          entity
          |> put_attribute(:priority, 7)
          |> trust()
          |> update()
        end)

      assert result == :ok
      assert DB.read(Module1, entity.id).priority == 7
    end

    test "deletes past the rules with a trust claim" do
      entity = DB.create!(Module1.new())

      trusted_entity = trust(entity)

      assert as_user(nil, fn -> delete(trusted_entity) end) == :ok
      assert DB.read(Module1, entity.id) == nil
    end
  end

  describe "create/1" do
    test "evaluates :create for the acting user" do
      user = create_user("author@example.com")
      entity = Module2.new(public: true)

      expected_msg =
        ~s(not allowed to create Hologram.Test.Fixtures.Policy.Module2 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> create(entity) end)
      end

      assert DB.read(Module2, entity.id) == nil
    end

    test "evaluates a type-wide role's rule for the acting user" do
      user = create_user("editor@example.com")
      Auth.grant_role(user, :editor, Module40)

      entity = Module40.new()

      assert {:ok, %Module40{}} = as_user(user, fn -> create(entity) end)
      assert DB.read(Module40, entity.id) != nil
    end

    # The related type's create rule is open, so a create asking it would pass - the delegation asks
    # whether the parent may be updated, which takes an editor.
    test "evaluates a delegation naming its operation against the related row" do
      user = create_user("delegated_creator@example.com")
      parent = DB.create!(PolicyModule10.new())
      entity = PolicyModule11.new(parent_id: parent.id)

      expected_msg =
        ~s(not allowed to create Hologram.Test.Fixtures.Policy.Module11 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> create(entity) end)
      end

      assert DB.read(PolicyModule11, entity.id) == nil

      Auth.grant_role(user, :editor, parent)

      assert {:ok, %PolicyModule11{}} = as_user(user, fn -> create(entity) end)
    end

    test "stamps a job with the acting user" do
      user = create_user("enqueuer@example.com")
      job = JobModule1.new()

      assert {:ok, %JobModule1{actor_id: actor_id}} = as_user(user, fn -> create(job) end)
      assert actor_id == user.id
      assert DB.read(JobModule1, job.id).actor_id == user.id
    end

    test "stamps a job with no actor without an acting user" do
      job = JobModule1.new()

      assert {:ok, %JobModule1{actor_id: nil}} = create(job)
      assert DB.read(JobModule1, job.id).actor_id == nil
    end

    test "stamps a job over the actor its struct carries" do
      user = create_user("stamped@example.com")
      job = %{JobModule1.new() | actor_id: Entity.generate_id()}

      assert {:ok, %JobModule1{actor_id: actor_id}} = as_user(user, fn -> create(job) end)
      assert actor_id == user.id
    end

    test "inserts raw without an acting user" do
      entity = Module2.new(public: true)

      assert {:ok, %Module2{created_at: %DateTime{}} = stamped_entity} = create(entity)
      assert unnumbered(DB.read(Module2, entity.id)) == stamped_entity
    end

    test "joins the enclosing transaction" do
      entity = Module2.new()

      assert DB.transaction(fn ->
               create(entity)

               DB.rollback(:abort)
             end) == {:error, :abort}

      assert DB.read(Module2, entity.id) == nil
    end

    test "returns an entity carrying no claim" do
      entity = trust(Module2.new())

      assert {:ok, %Module2{__meta__: %Metadata{claim: nil}}} = create(entity)
    end

    test "stores the stamp the struct carries" do
      # Far past anything this node's clock would answer, so a stamp taken here rather than given
      # cannot coincide with it.
      stamp = 4_000_000_000_000_000

      entity =
        %{public: true}
        |> Module2.new()
        |> trust()
        |> Map.update!(:__meta__, &%{&1 | stamp: stamp})

      assert {:ok, created_entity} = create(entity)

      assert EntityOperations.get(Module2, created_entity.id).__meta__.revisions == %{
               public: stamp
             }
    end

    for user_id <- [7, "abc"] do
      test "writes a row a visitor may create under the user id #{inspect(user_id)}, recording no actor" do
        entity = Module9.new()

        assert {:ok, %Module9{}} = as_user(unquote(user_id), fn -> create(entity) end)
        assert DB.read(Module9, entity.id) != nil
        assert oplog_actor_ids(entity.id) == [nil]
      end
    end

    test "evaluates :create as a visitor's under a user id no user entity can have" do
      entity = Module2.new(public: true)

      expected_msg =
        ~s(not allowed to create Hologram.Test.Fixtures.Policy.Module2 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(7, fn -> create(entity) end)
      end

      assert DB.read(Module2, entity.id) == nil
    end

    test "grants no creator role under a user id no user entity can have" do
      entity = trust(Module1.new())

      assert {:ok, %Module1{}} = as_user(7, fn -> create(entity) end)

      {:ok, %Postgrex.Result{rows: [[count]]}} =
        Connection.query(
          ~s|SELECT count(*) FROM "hologram_data"."hologram_role_grant" WHERE "entity_id" = $1|,
          [Codec.encode(entity.id, :uuid)]
        )

      assert count == 0
    end

    test "creates a job under a user id no user entity can have, to run under the rules" do
      job = JobModule1.new()

      assert {:ok, %JobModule1{actor_id: nil, run_as_server: false}} =
               as_user(7, fn -> create(job) end)

      assert %{actor_id: nil, run_as_server: false} = DB.read(JobModule1, job.id)
    end

    test "creates a job claiming trust under a user id no user entity can have, as the server" do
      job = trust(JobModule1.new())

      assert {:ok, %JobModule1{actor_id: nil, run_as_server: true}} =
               as_user(7, fn -> create(job) end)

      assert %{actor_id: nil, run_as_server: true} = DB.read(JobModule1, job.id)
    end

    test "creates a job through Job.create/3 under a user id no user entity can have" do
      assert {:ok, %JobModule1{actor_id: nil, run_as_server: false}} =
               as_user(7, fn -> Job.create(JobModule1) end)
    end

    test "creates a job through Job.create/3 claiming trust under a user id no user entity can have" do
      assert {:ok, %JobModule1{actor_id: nil, run_as_server: true}} =
               as_user(7, fn -> Job.create(JobModule1, %{}, trust: true) end)
    end

    # A browser's write is never the server's, whatever state the process is in.
    test "leaves a client's job unmarked with no session" do
      job = JobModule1.new()
      %Metadata{} = metadata = job.__meta__
      client_job = %{job | __meta__: %{metadata | claim: :client}}

      assert {:ok, %JobModule1{run_as_server: false}} = create(client_job)
      assert DB.read(JobModule1, job.id).run_as_server == false
    end

    # The stamp is the write's own, so a value the struct carries can't choose how the job runs.
    test "stamps a job's server mark over what the struct carries" do
      job = %{JobModule1.new() | run_as_server: true}

      assert {:ok, %JobModule1{run_as_server: false}} = as_user(nil, fn -> create(job) end)
      assert DB.read(JobModule1, job.id).run_as_server == false
    end

    test "skips evaluation for a trust claim and still grants creator roles" do
      user = create_user("creator@example.com")

      entity = trust(Module1.new())

      assert {:ok, %Module1{}} = as_user(user, fn -> create(entity) end)
      assert granted_roles(user.id, entity.id) == ["maintainer", "owner"]
    end
  end

  describe "delete/1" do
    test "deletes raw without an acting user" do
      entity = DB.create!(Module1.new())

      assert delete(entity) == :ok
      assert DB.read(Module1, entity.id) == nil
    end

    test "evaluates :delete for the acting user" do
      user = create_user("deleter@example.com")

      parent = DB.create!(Module2.new())

      entity =
        %{parent_id: parent.id}
        |> Module1.new()
        |> DB.create!()

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> delete(entity) end)
      end

      assert DB.read(Module1, entity.id) != nil

      # allow :delete, to: {:admin, parent} - the grant is on the PARENT, not the row.
      Auth.grant_role(user, :admin, parent)

      assert as_user(user, fn -> delete(entity) end) == :ok
      assert DB.read(Module1, entity.id) == nil
    end

    test "evaluates the rules against the row as it stands, not the struct in hand" do
      user = create_user("mover@example.com")

      granting_parent = DB.create!(Module2.new())

      other_parent = DB.create!(Module2.new())

      entity =
        %{parent_id: granting_parent.id}
        |> Module1.new()
        |> DB.create!()

      # allow :delete, to: {:admin, parent} - the role is granted on the parent the STRUCT
      # names, while the row has since been moved to a parent the user has no role on.
      Auth.grant_role(user, :admin, granting_parent)
      EntityOperations.update(Module1, entity.id, parent_id: other_parent.id)

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> delete(entity) end)
      end

      assert DB.read(Module1, entity.id) != nil
    end

    test "skips evaluation for a trust claim" do
      user = create_user("purger@example.com")

      entity = DB.create!(Module1.new())

      assert as_user(user, fn -> delete(trust(entity)) end) == :ok
      assert DB.read(Module1, entity.id) == nil
    end

    test "is a no-op for an id naming no row, evaluating nothing" do
      user = create_user("ghost@example.com")

      assert delete(Module1.new()) == :ok
      assert as_user(user, fn -> delete(Module1.new()) end) == :ok
    end

    test "names the referencer when an incoming reference blocks the delete" do
      source = DB.create!(Module16.new())

      target =
        %{token: "t"}
        |> Module15.new()
        |> DB.create!()

      source
      |> add_relationship(:secrets, target.id)
      |> update()

      assert delete(target) == {:error, %{referenced_by: Module16, relationship: :secrets}}
      assert count_edges(source, target) == 1
    end
  end

  describe "delete/2" do
    test "deletes raw without an acting user" do
      entity = DB.create!(Module1.new())

      assert delete(Module1, entity.id) == :ok
      assert DB.read(Module1, entity.id) == nil
    end

    test "evaluates :delete for the acting user" do
      user = create_user("id_deleter@example.com")

      parent = DB.create!(Module2.new())

      entity =
        %{parent_id: parent.id}
        |> Module1.new()
        |> DB.create!()

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> delete(Module1, entity.id) end)
      end

      assert DB.read(Module1, entity.id) != nil

      Auth.grant_role(user, :admin, parent)

      assert as_user(user, fn -> delete(Module1, entity.id) end) == :ok
      assert DB.read(Module1, entity.id) == nil
    end

    test "is a no-op for an id naming no row" do
      user = create_user("id_ghost@example.com")

      assert as_user(user, fn -> delete(Module1, Entity.generate_id()) end) == :ok
    end
  end

  describe "update/1" do
    test "refuses each attribute the framework sets on a job, even with a trust claim" do
      job = Job.create!(JobModule1)

      for {name, value} <- job_framework_values() do
        expected_msg =
          "#{inspect(name)} of Hologram.Test.Fixtures.Job.Module1 is set by the framework - an update can't change it"

        assert_error MisuseError, expected_msg, fn ->
          job
          |> put_attribute(name, value)
          |> trust()
          |> update()
        end
      end

      assert DB.read(JobModule1, job.id).run_as_server == true
    end

    test "a denied write rolls back the writes made before it" do
      user = create_user("roller@example.com")
      earlier_entity = Module1.new()

      target =
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module1 "#{target.id}" - no allow line that holds covers :public)

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn ->
          DB.transaction(fn ->
            earlier_entity
            |> trust()
            |> create()

            target
            |> put_attribute(:public, true)
            |> update()
          end)
        end)
      end

      assert DB.read(Module1, earlier_entity.id) == nil
      assert DB.read(Module1, target.id).public == false
    end

    test "applies changes and relationship ops under one transaction - a refused value applies no op" do
      source = DB.create!(Module16.new())

      target =
        %{token: "t"}
        |> Module15.new()
        |> DB.create!()

      entity =
        source
        |> put_attribute(:name, wrap_term(123))
        |> add_relationship(:secrets, target.id)

      assert {:error, %{name: [{:type, :string}]}} = update(entity)
      assert count_edges(source, target) == 0
    end

    test "applies recorded relationship ops in the same transaction" do
      source = DB.create!(Module16.new())

      target =
        %{token: "t"}
        |> Module15.new()
        |> DB.create!()

      assert source
             |> add_relationship(:secrets, target.id)
             |> update() == :ok

      assert count_edges(source, target) == 1
    end

    test "applies a recorded delete op" do
      source = DB.create!(Module16.new())

      target =
        %{token: "t"}
        |> Module15.new()
        |> DB.create!()

      source
      |> add_relationship(:secrets, target.id)
      |> update()

      assert source
             |> delete_relationship(:secrets, target.id)
             |> update() == :ok

      assert count_edges(source, target) == 0
    end

    test "evaluates :update for the acting user against the row as it stands" do
      user = create_user("editor@example.com")

      entity =
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()

      Auth.grant_role(user, :editor, entity)

      assert as_user(user, fn ->
               entity
               |> put_attribute(:public, true)
               |> update()
             end) == :ok

      # The rule reads the row as it stands, not the struct in hand: the test still holds
      # priority 5 while the row now shows 1, and allow :update wants at least 3.
      EntityOperations.update(Module1, entity.id, priority: 1)

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}" - no allow line that holds covers :public)

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn ->
          entity
          |> put_attribute(:public, false)
          |> update()
        end)
      end

      assert DB.read(Module1, entity.id).public == true
    end

    test "skips evaluation for a trust claim" do
      user = create_user("recorder@example.com")

      entity =
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()

      assert as_user(user, fn ->
               entity
               |> put_attribute(:priority, 9)
               |> trust()
               |> update()
             end) == :ok

      assert DB.read(Module1, entity.id).priority == 9
    end

    test "writes the recorded changes raw without an acting user" do
      entity =
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()

      assert entity
             |> put_attribute(:priority, 7)
             |> update() == :ok

      reloaded_entity = DB.read(Module1, entity.id)

      assert reloaded_entity.priority == 7
      assert reloaded_entity.public == entity.public
    end

    test "writes a to-one reference field" do
      entity = DB.create!(Module1.new())

      parent = DB.create!(Module2.new())

      assert entity
             |> put_attribute(:parent_id, parent.id)
             |> update() == :ok

      assert DB.read(Module1, entity.id).parent_id == parent.id
    end

    test "records the value a moved reference field held before the update" do
      first_parent = DB.create!(Module2.new())
      second_parent = DB.create!(Module2.new())

      entity =
        %{parent_id: first_parent.id}
        |> Module1.new()
        |> DB.create!()

      assert entity
             |> put_attribute(:parent_id, second_parent.id)
             |> update() == :ok

      assert last_old_references() == %{"parent_id" => first_parent.id}
    end

    test "stores the stamp the struct carries on the columns it sets" do
      entity =
        %{priority: 1}
        |> Module1.new()
        |> DB.create!()

      stamp = entity.__meta__.revisions.priority + 1_000_000

      assert entity
             |> put_attribute(:priority, 2)
             |> Map.update!(:__meta__, &%{&1 | stamp: stamp})
             |> update() == :ok

      revisions = EntityOperations.get(Module1, entity.id).__meta__.revisions

      assert revisions.priority == stamp
      assert revisions.public == entity.__meta__.revisions.public
    end

    test "moves the recorded deltas" do
      entity =
        %{count: 5}
        |> Module10.new()
        |> DB.create!()

      assert entity
             |> put_attribute(:bio, "moved")
             |> increment(:count, 2)
             |> update() == :ok

      updated_entity = EntityOperations.get(Module10, entity.id)

      assert updated_entity.bio == "moved"
      assert updated_entity.count == 7
    end

    test "moves a recorded delta alone" do
      entity =
        %{count: 5}
        |> Module10.new()
        |> DB.create!()

      assert entity
             |> decrement(:count, 1)
             |> update() == :ok

      assert EntityOperations.get(Module10, entity.id).count == 4
    end

    test "stores the stamp the struct carries on a moved column" do
      entity =
        %{count: 5}
        |> Module10.new()
        |> DB.create!()

      stamp = entity.__meta__.revisions.count + 1_000_000

      assert entity
             |> increment(:count, 1)
             |> Map.update!(:__meta__, &%{&1 | stamp: stamp})
             |> update() == :ok

      assert EntityOperations.get(Module10, entity.id).__meta__.revisions.count == stamp
    end

    test "returns a violation for a move by an amount its column can't hold" do
      entity =
        %{count: -5_000_000_000_000_000_000}
        |> Module20.new()
        |> DB.create!()

      assert entity
             |> increment(:count, 10_000_000_000_000_000_000)
             |> update() == {:error, %{count: [{:type, :integer}]}}

      assert EntityOperations.get(Module20, entity.id).count == -5_000_000_000_000_000_000
    end

    test "returns the violation a moved value's declaration refuses" do
      entity =
        %{count: 1}
        |> Module10.new()
        |> DB.create!()

      assert entity
             |> decrement(:count, 1)
             |> update() == {:error, %{count: [{:min, 1}]}}

      assert EntityOperations.get(Module10, entity.id).count == 1
    end

    test "raises when nothing is recorded" do
      entity = DB.create!(Module1.new())

      expected_msg =
        "update takes recorded changes - put values with put_attribute, move counters with " <>
          "increment or decrement, and edges with add_relationship or delete_relationship. " <>
          "A field set directly on the struct is not recorded: writing the whole struct " <>
          "would overwrite concurrent changes to fields you didn't touch."

      assert_error MisuseError, expected_msg, fn -> update(%{entity | public: true}) end
    end

    test "raises when the row does not exist" do
      entity = Module1.new()

      expected_msg =
        ~s(cannot update Hologram.Test.Fixtures.Policy.Module1 - no entity with id "#{entity.id}")

      assert_error MisuseError, expected_msg, fn ->
        entity
        |> put_attribute(:public, true)
        |> update()
      end
    end

    test "returns the violation the update validator refuses" do
      entity = DB.create!(Module1.new())

      assert {:error, %{priority: [{:type, :integer}]}} =
               entity
               |> put_attribute(:priority, wrap_term("x"))
               |> update()
    end
  end

  # Policy.Module38 lets anyone set the topic and the tags while a channel isn't archived, its owner
  # rename it and move it to a parent, anyone change all but :archived and :owner on a channel named
  # "open", and its owner change anything once it is archived.
  describe "update/1 of the fields a line covers" do
    defp create_channel(values) do
      values
      |> Channel.new()
      |> DB.create!()
    end

    defp denied_fields(channel, fields) do
      ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module38 "#{channel.id}" - no allow line that holds covers #{fields})
    end

    test "lands a change of a field a holding line covers" do
      member = create_user("field-member-1@example.com")
      channel = create_channel(name: "general")

      assert as_user(member, fn ->
               channel
               |> put_attribute(:topic, "news")
               |> update()
             end) ==
               :ok

      assert DB.read(Channel, channel.id).topic == "news"
    end

    test "refuses a change of a field no holding line covers, naming it" do
      member = create_user("field-member-2@example.com")
      channel = create_channel(name: "general")

      assert_error AccessDeniedError, denied_fields(channel, ":name"), fn ->
        as_user(member, fn ->
          channel
          |> put_attribute(:name, "mine")
          |> update()
        end)
      end

      assert DB.read(Channel, channel.id).name == "general"
    end

    test "refuses a write mixing covered and uncovered fields, naming the uncovered ones" do
      member = create_user("field-member-3@example.com")
      channel = create_channel(name: "general")

      assert_error AccessDeniedError, denied_fields(channel, ":name, :parent"), fn ->
        as_user(member, fn ->
          channel
          |> put_attribute(:topic, "news")
          |> put_attribute(:name, "mine")
          |> put_attribute(:parent_id, nil)
          |> update()
        end)
      end

      assert DB.read(Channel, channel.id).topic == nil
    end

    test "lands a write whose fields different lines cover" do
      owner = create_user("field-owner-1@example.com")
      channel = create_channel(name: "general", owner_id: owner.id)

      assert as_user(owner, fn ->
               channel
               |> put_attribute(:topic, "news")
               |> put_attribute(:name, "renamed")
               |> update()
             end) == :ok

      assert %{name: "renamed", topic: "news"} = DB.read(Channel, channel.id)
    end

    test "covers a to-one's reference field by its relationship's name" do
      owner = create_user("field-owner-2@example.com")
      member = create_user("field-member-4@example.com")

      parent =
        []
        |> Module36.new()
        |> DB.create!()

      channel = create_channel(name: "general", owner_id: owner.id)

      assert as_user(owner, fn ->
               channel
               |> put_attribute(:parent_id, parent.id)
               |> update()
             end) == :ok

      assert_error AccessDeniedError, denied_fields(channel, ":parent"), fn ->
        as_user(member, fn ->
          channel
          |> put_attribute(:parent_id, nil)
          |> update()
        end)
      end
    end

    test "covers an edge of a to-many by its relationship's name" do
      member = create_user("field-member-5@example.com")

      tag =
        [token: "t"]
        |> Module15.new()
        |> DB.create!()

      open = create_channel(name: "general")
      archived = create_channel(name: "general", archived: true)

      assert as_user(member, fn ->
               open
               |> add_relationship(:tags, tag.id)
               |> update()
             end) == :ok

      assert_error AccessDeniedError, denied_fields(archived, ":tags"), fn ->
        as_user(member, fn ->
          archived
          |> add_relationship(:tags, tag.id)
          |> update()
        end)
      end
    end

    test "covers a counter moved by an amount" do
      member = create_user("field-member-6@example.com")
      open = create_channel(name: "open")
      general = create_channel(name: "general")

      assert as_user(member, fn ->
               open
               |> increment(:sent_count, 1)
               |> update()
             end) == :ok

      assert DB.read(Channel, open.id).sent_count == 1

      assert_error AccessDeniedError, denied_fields(general, ":sent_count"), fn ->
        as_user(member, fn ->
          general
          |> increment(:sent_count, 1)
          |> update()
        end)
      end
    end

    test "covers every field but the ones an except line lists" do
      member = create_user("field-member-7@example.com")
      channel = create_channel(name: "open")

      assert as_user(member, fn ->
               channel
               |> put_attribute(:name, "lobby")
               |> update()
             end) ==
               :ok

      lobby = DB.read(Channel, channel.id)
      reopened = create_channel(name: "open")

      assert_error AccessDeniedError, denied_fields(reopened, ":archived"), fn ->
        as_user(member, fn ->
          reopened
          |> put_attribute(:archived, true)
          |> update()
        end)
      end

      assert lobby.name == "lobby"
    end

    test "covers every field with a line covering the whole row" do
      owner = create_user("field-owner-3@example.com")
      other = create_user("field-other-1@example.com")
      channel = create_channel(name: "general", owner_id: owner.id, archived: true)

      assert as_user(owner, fn ->
               channel
               |> put_attribute(:archived, false)
               |> put_attribute(:owner_id, other.id)
               |> update()
             end) == :ok

      assert %{archived: false, owner_id: owner_id} = DB.read(Channel, channel.id)
      assert owner_id == other.id
    end

    # Module39 delegates its update to the channel's :update, which the lines covering the whole row
    # answer alone - so setting a channel's topic grants nothing on its messages.
    test "counts no field-limited line for a delegation asking :update" do
      member = create_user("field-member-8@example.com")
      channel = create_channel(name: "general")

      message =
        [channel_id: channel.id]
        |> ChannelMessage.new()
        |> DB.create!()

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module39 "#{message.id}" - no allow line that holds covers :body)

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(member, fn ->
          message
          |> put_attribute(:body, "hi")
          |> update()
        end)
      end
    end
  end

  describe "update/1 of rules reading the row after the change" do
    defp create_changed_task(values \\ %{}) do
      task =
        values
        |> ChangedTask.new()
        |> DB.create!()

      EntityOperations.get(ChangedTask, task.id)
    end

    defp create_changed_project(archived \\ false) do
      %{archived: archived}
      |> ChangedProject.new()
      |> DB.create!()
    end

    defp create_changed_label(blocked) do
      %{blocked: blocked}
      |> ChangedLabel.new()
      |> DB.create!()
    end

    defp uncovered_message(task, field) do
      "not allowed to update #{inspect(ChangedTask)} #{inspect(task.id)} - no allow line that holds covers #{inspect(field)}"
    end

    test "lets a change through to the value the rule allows" do
      user = create_user("approver@example.com")
      task = create_changed_task()
      Auth.grant_role(user, :admin, task)

      assert as_user(user, fn -> update(put_attribute(task, :status, :approved)) end) == :ok
      assert EntityOperations.get(ChangedTask, task.id).status == :approved
    end

    test "refuses a change to a value the rule doesn't allow" do
      user = create_user("rejecter@example.com")
      task = create_changed_task()
      Auth.grant_role(user, :admin, task)

      assert_error AccessDeniedError, uncovered_message(task, :status), fn ->
        as_user(user, fn -> update(put_attribute(task, :status, :rejected)) end)
      end
    end

    test "still reads a bare name as the stored value" do
      user = create_user("reapprover@example.com")
      task = create_changed_task(%{status: :rejected})
      Auth.grant_role(user, :admin, task)

      assert_error AccessDeniedError, uncovered_message(task, :status), fn ->
        as_user(user, fn -> update(put_attribute(task, :status, :approved)) end)
      end
    end

    test "moves a row between two projects the user is a member of" do
      user = create_user("mover@example.com")
      source = create_changed_project()
      target = create_changed_project()
      task = create_changed_task(%{project_id: source.id})
      Auth.grant_role(user, :member, source)
      Auth.grant_role(user, :member, target)

      assert as_user(user, fn -> update(put_attribute(task, :project_id, target.id)) end) == :ok

      assert EntityOperations.get(ChangedTask, task.id).project_id == target.id
    end

    test "refuses a move into a project the user isn't a member of" do
      user = create_user("intruder@example.com")
      source = create_changed_project()
      target = create_changed_project()
      task = create_changed_task(%{project_id: source.id})
      Auth.grant_role(user, :member, source)

      assert_error AccessDeniedError, uncovered_message(task, :project), fn ->
        as_user(user, fn -> update(put_attribute(task, :project_id, target.id)) end)
      end
    end

    test "refuses a move out of a project the user isn't a member of" do
      user = create_user("outsider@example.com")
      source = create_changed_project()
      target = create_changed_project()
      task = create_changed_task(%{project_id: source.id})
      Auth.grant_role(user, :member, target)

      assert_error AccessDeniedError, uncovered_message(task, :project), fn ->
        as_user(user, fn -> update(put_attribute(task, :project_id, target.id)) end)
      end
    end

    test "judges a counter by the value it moves to" do
      user = create_user("counter@example.com")
      task = create_changed_task(%{count: 9})

      assert as_user(user, fn -> update(increment(task, :count, 1)) end) == :ok

      moved = EntityOperations.get(ChangedTask, task.id)

      assert moved.count == 10

      assert_error AccessDeniedError, uncovered_message(task, :count), fn ->
        as_user(user, fn -> update(increment(moved, :count, 1)) end)
      end
    end

    test "moves the timestamp a rule reads for a write that admits a value" do
      user = create_user("marker@example.com")
      task = with_past_updated_at(create_changed_task())

      assert as_user(user, fn -> update(put_attribute(task, :mark, "ok")) end) == :ok
    end

    test "leaves the timestamp a rule reads as stored when no value is admitted" do
      user = create_user("invalid_marker@example.com")
      task = with_past_updated_at(create_changed_task())

      expected_msg =
        uncovered_message(task, :mark) <>
          " (the value given for :mark is invalid, so its rule read the stored value)"

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> update(put_attribute(task, :mark, "too long")) end)
      end
    end

    test "reads a field the change doesn't touch as stored" do
      user = create_user("noter@example.com")
      archived = create_changed_project(true)
      task = create_changed_task(%{project_id: archived.id})

      assert_error AccessDeniedError, uncovered_message(task, :note), fn ->
        as_user(user, fn -> update(put_attribute(task, :note, "x")) end)
      end
    end

    test "judges a to-many by the edges the call adds" do
      user = create_user("labeler@example.com")
      task = create_changed_task()
      plain = create_changed_label(false)
      blocked = create_changed_label(true)

      assert as_user(user, fn -> update(add_relationship(task, :labels, plain.id)) end) == :ok

      assert_error AccessDeniedError, uncovered_message(task, :labels), fn ->
        as_user(user, fn -> update(add_relationship(task, :labels, blocked.id)) end)
      end
    end

    test "answers an invalid value with its violations when its rule holds" do
      user = create_user("invalid@example.com")
      project = create_changed_project()
      task = create_changed_task(%{project_id: project.id})
      Auth.grant_role(user, :member, project)

      assert {:error, %{code: [_violation]}} =
               as_user(user, fn -> update(put_attribute(task, :code, "too long")) end)
    end

    test "says a refused field's value was invalid" do
      user = create_user("invalid_status@example.com")
      task = create_changed_task()
      Auth.grant_role(user, :admin, task)

      expected_msg =
        uncovered_message(task, :status) <>
          " (the value given for :status is invalid, so its rule read the stored value)"

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> update(put_attribute(task, :status, :bogus)) end)
      end
    end

    test "says so for each refused field whose value was invalid" do
      user = create_user("invalid_outsider@example.com")
      task = create_changed_task()

      expected_msg =
        "not allowed to update #{inspect(ChangedTask)} #{inspect(task.id)} - no allow line that holds covers :code, :status (the values given for :code, :status are invalid, so their rules read the stored values)"

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn ->
          task
          |> put_attribute(:code, "too long")
          |> put_attribute(:status, :bogus)
          |> update()
        end)
      end
    end

    test "names a relationship whose reference was malformed" do
      user = create_user("malformed_reference@example.com")
      task = create_changed_task()

      expected_msg =
        uncovered_message(task, :project) <>
          " (the value given for :project is invalid, so its rule read the stored value)"

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> update(put_attribute(task, :project_id, "not-a-uuid")) end)
      end
    end

    test "doesn't say a refused reference names no row" do
      user = create_user("missing_outsider@example.com")
      task = create_changed_task()
      missing_id = Entity.generate_id()

      assert_error AccessDeniedError, uncovered_message(task, :project), fn ->
        as_user(user, fn -> update(put_attribute(task, :project_id, missing_id)) end)
      end
    end

    test "judges a reference naming no row on the stored one" do
      user = create_user("missing_target@example.com")
      project = create_changed_project()
      task = create_changed_task(%{project_id: project.id})
      Auth.grant_role(user, :member, project)
      missing_id = Entity.generate_id()

      assert {:error, %{project_id: [:not_found]}} =
               as_user(user, fn -> update(put_attribute(task, :project_id, missing_id)) end)
    end

    test "answers a move past what the column holds with its violation when the stored value passes" do
      user = create_user("overflowing_counter@example.com")
      task = create_changed_task(%{count: 5})

      assert as_user(user, fn ->
               update(increment(task, :count, 9_223_372_036_854_775_807))
             end) == {:error, %{count: [{:type, :integer}]}}

      assert EntityOperations.get(ChangedTask, task.id).count == 5
    end

    test "answers an amount the column can't take with its violation when the stored value passes" do
      user = create_user("huge_amount@example.com")
      task = create_changed_task(%{count: -5_000_000_000_000_000_000})

      assert as_user(user, fn ->
               update(increment(task, :count, 10_000_000_000_000_000_000))
             end) == {:error, %{count: [{:type, :integer}]}}
    end

    test "says a refused move was invalid when the stored value fails too" do
      user = create_user("overflowing_refused@example.com")
      task = create_changed_task(%{count: 11})

      expected_msg =
        uncovered_message(task, :count) <>
          " (the value given for :count is invalid, so its rule read the stored value)"

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> update(increment(task, :count, 9_223_372_036_854_775_807)) end)
      end
    end

    test "judges nothing on the trusted tier" do
      task = create_changed_task()

      assert update(put_attribute(task, :status, :rejected)) == :ok
    end
  end

  describe "update/3 of rules reading the row after the change" do
    test "judges the values it's given" do
      user = create_user("indexed@example.com")
      task = create_changed_task()
      Auth.grant_role(user, :admin, task)

      assert_error AccessDeniedError, uncovered_message(task, :status), fn ->
        as_user(user, fn -> update(ChangedTask, task.id, status: :rejected) end)
      end

      assert as_user(user, fn -> update(ChangedTask, task.id, status: :approved) end) == :ok
    end
  end

  describe "update/3" do
    test "refuses each attribute the framework sets on a job, with no session" do
      job = Job.create!(JobModule1)

      for {name, value} <- job_framework_values() do
        expected_msg =
          "#{inspect(name)} of Hologram.Test.Fixtures.Job.Module1 is set by the framework - an update can't change it"

        assert_error MisuseError, expected_msg, fn ->
          update(JobModule1, job.id, [{name, value}])
        end
      end
    end

    test "refuses a job's actor in a session" do
      job = Job.create!(JobModule1)

      expected_msg =
        ":actor_id of Hologram.Test.Fixtures.Job.Module1 is set by the framework - an update can't change it"

      assert_error MisuseError, expected_msg, fn ->
        as_user(nil, fn -> update(JobModule1, job.id, actor_id: nil) end)
      end
    end

    test "raises for a role grant without an acting user" do
      expected_msg =
        "cannot update Hologram.Auth.RoleGrant - a role grant is never changed in place, revoke the role and grant the new one instead"

      assert_error MisuseError, expected_msg, fn ->
        update(RoleGrant, Entity.generate_id(), %{role: :editor})
      end
    end

    test "raises for a role grant under an acting user" do
      user = create_user("grant-updater@example.com")

      expected_msg =
        "cannot update Hologram.Auth.RoleGrant - a role grant is never changed in place, revoke the role and grant the new one instead"

      assert_error MisuseError, expected_msg, fn ->
        as_user(user, fn -> update(RoleGrant, Entity.generate_id(), %{role: :editor}) end)
      end
    end

    test "writes raw without an acting user" do
      entity =
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()

      assert update(Module1, entity.id, priority: 7) == :ok
      assert DB.read(Module1, entity.id).priority == 7
    end

    test "evaluates :update for the acting user" do
      user = create_user("id_editor@example.com")

      entity =
        %{priority: 5}
        |> Module1.new()
        |> DB.create!()

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}" - no allow line that holds covers :public)

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> update(Module1, entity.id, public: true) end)
      end

      assert DB.read(Module1, entity.id).public == false

      Auth.grant_role(user, :editor, entity)

      assert as_user(user, fn -> update(Module1, entity.id, public: true) end) == :ok
      assert DB.read(Module1, entity.id).public == true
    end

    test "judges the fields it changes, a reference field by its relationship's name" do
      member = create_user("type-indexed-member@example.com")

      channel =
        [name: "general"]
        |> Channel.new()
        |> DB.create!()

      assert as_user(member, fn -> update(Channel, channel.id, topic: "news") end) == :ok

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module38 "#{channel.id}" - no allow line that holds covers :name, :parent)

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(member, fn -> update(Channel, channel.id, name: "mine", parent_id: nil) end)
      end
    end

    test "refuses a misspelt field as misuse before judging it" do
      member = create_user("type-indexed-typo@example.com")

      channel =
        [name: "general"]
        |> Channel.new()
        |> DB.create!()

      expected_msg =
        "invalid changes for Hologram.Test.Fixtures.Policy.Module38 - only declared attributes and to-one relationships can be updated: :titel"

      assert_error MisuseError, expected_msg, fn ->
        as_user(member, fn -> update(Channel, channel.id, titel: "x") end)
      end
    end

    test "raises when the row does not exist" do
      user = create_user("id_missing@example.com")
      id = Entity.generate_id()

      expected_msg =
        ~s(cannot update Hologram.Test.Fixtures.Policy.Module1 - no entity with id "#{id}")

      assert_error MisuseError, expected_msg, fn ->
        as_user(user, fn -> update(Module1, id, public: true) end)
      end
    end
  end
end
