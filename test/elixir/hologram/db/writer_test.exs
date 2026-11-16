defmodule Hologram.DB.WriterTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.Writer

  import Hologram.Query,
    only: [
      add_relationship: 3,
      authorize: 2,
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
  alias Hologram.MisuseError
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module16
  alias Hologram.Test.Fixtures.Job.Module1, as: JobModule1
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module10, as: PolicyModule10
  alias Hologram.Test.Fixtures.Policy.Module11, as: PolicyModule11
  alias Hologram.Test.Fixtures.Policy.Module2
  alias Hologram.Test.Fixtures.Policy.Module36
  alias Hologram.Test.Fixtures.Policy.Module38, as: Channel
  alias Hologram.Test.Fixtures.Policy.Module39, as: ChannelMessage

  defp create_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
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

  defp last_old_references do
    statement = ~s|SELECT "old" FROM "hologram_system"."oplog" ORDER BY "seq" DESC LIMIT 1|

    {:ok, %Postgrex.Result{rows: [[old]]}} = Connection.query(statement)

    old
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
      user = create_user("admin@example.com")
      Auth.grant_role(user, :admin, Module2)

      entity = authorize(Module2.new(), :update)

      assert {:ok, %Module2{}} = as_user(user, fn -> create(entity) end)
      assert DB.read(Module2, entity.id) != nil
    end

    test "evaluates an explicit claim without an acting user with the anonymous semantics" do
      granted_entity =
        %{public: true}
        |> Module2.new()
        |> authorize(:publish)

      assert {:ok, %Module2{}} = create(granted_entity)

      denied_entity =
        %{public: true}
        |> Module2.new()
        |> authorize(:update)

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module2 "#{denied_entity.id}")

      assert_error AccessDeniedError, expected_msg, fn -> create(denied_entity) end
    end

    test "evaluates the operation the entity claims against the row being inserted" do
      user = create_user("publisher@example.com")

      granted_entity =
        %{public: true}
        |> Module2.new()
        |> authorize(:publish)

      assert {:ok, %Module2{}} = as_user(user, fn -> create(granted_entity) end)

      denied_entity =
        %{public: false}
        |> Module2.new()
        |> authorize(:publish)

      expected_msg =
        ~s(not allowed to publish Hologram.Test.Fixtures.Policy.Module2 "#{denied_entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> create(denied_entity) end)
      end

      assert DB.read(Module2, denied_entity.id) == nil
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
      assert DB.read(Module2, entity.id) == stamped_entity
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

    test "evaluates the claim against the row as it stands, not the struct in hand" do
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

    test "evaluates the operation the entity claims" do
      user = create_user("archiver@example.com")

      entity =
        %{author_id: user.id}
        |> Module1.new()
        |> DB.create!()

      claimed_entity = authorize(entity, :archive)

      assert as_user(user, fn -> delete(claimed_entity) end) == :ok
      assert DB.read(Module1, entity.id) == nil
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
    test "a denied claim rolls back the writes made before it" do
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

    test "evaluates the operation the entity claims" do
      user = create_user("archivist@example.com")

      own_entity =
        %{author_id: user.id}
        |> Module1.new()
        |> DB.create!()

      assert as_user(user, fn ->
               own_entity
               |> put_attribute(:public, true)
               |> authorize(:archive)
               |> update()
             end) == :ok

      other_entity = DB.create!(Module1.new())

      expected_msg =
        ~s(not allowed to archive Hologram.Test.Fixtures.Policy.Module1 "#{other_entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn ->
          other_entity
          |> put_attribute(:public, true)
          |> authorize(:archive)
          |> update()
        end)
      end
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

  describe "update/3" do
    test "raises for a role grant without an acting user" do
      expected_msg =
        "cannot update Hologram.Auth.RoleGrant - a role grant is never changed in place, revoke the role and grant the new one instead"

      assert_error MisuseError, expected_msg, fn ->
        update(RoleGrant, Entity.generate_id(), %{role: :editor})
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
