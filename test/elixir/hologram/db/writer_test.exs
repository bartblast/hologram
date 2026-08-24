defmodule Hologram.DB.WriterTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.Writer

  import Hologram.Query,
    only: [add_relationship: 3, authorize: 2, delete_relationship: 3, put_attribute: 3, trust: 1]

  import Hologram.Test, only: [as_user: 2]

  alias Hologram.AccessDeniedError
  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module16
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module2

  defp create_user(email) do
    Module14
    |> Entity.new(email: email)
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

  defp granted_roles(user_id, resource_id) do
    select_sql =
      ~s|SELECT "role" FROM "hologram_data"."hologram_role_grant" | <>
        ~s|WHERE "user_id" = $1 AND "resource_id" = $2 ORDER BY "role"|

    {:ok, %{rows: rows}} =
      Connection.query(select_sql, [
        Codec.encode(user_id, :uuid),
        Codec.encode(resource_id, :uuid)
      ])

    Enum.map(rows, fn [role] -> role end)
  end

  describe "create/1" do
    test "evaluates :create for the acting user" do
      user = create_user("author@example.com")
      entity = Entity.new(Module2, public: true)

      expected_msg =
        ~s(not allowed to create Hologram.Test.Fixtures.Policy.Module2 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> create(entity) end)
      end

      assert DB.get(Module2, entity.id) == nil
    end

    test "evaluates a type-wide role's rule for the acting user" do
      user = create_user("admin@example.com")
      Auth.grant_role(user, Module2, :admin)

      entity =
        Module2
        |> Entity.new()
        |> authorize(:update)

      assert {:ok, %Module2{}} = as_user(user, fn -> create(entity) end)
      assert DB.get(Module2, entity.id) != nil
    end

    test "evaluates an explicit claim without an acting user with the anonymous semantics" do
      granted_entity =
        Module2
        |> Entity.new(public: true)
        |> authorize(:publish)

      assert {:ok, %Module2{}} = create(granted_entity)

      denied_entity =
        Module2
        |> Entity.new(public: true)
        |> authorize(:update)

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module2 "#{denied_entity.id}")

      assert_error AccessDeniedError, expected_msg, fn -> create(denied_entity) end
    end

    test "evaluates the operation the entity claims against the row being inserted" do
      user = create_user("publisher@example.com")

      granted_entity =
        Module2
        |> Entity.new(public: true)
        |> authorize(:publish)

      assert {:ok, %Module2{}} = as_user(user, fn -> create(granted_entity) end)

      denied_entity =
        Module2
        |> Entity.new(public: false)
        |> authorize(:publish)

      expected_msg =
        ~s(not allowed to publish Hologram.Test.Fixtures.Policy.Module2 "#{denied_entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> create(denied_entity) end)
      end

      assert DB.get(Module2, denied_entity.id) == nil
    end

    test "inserts raw without an acting user" do
      entity = Entity.new(Module2, public: true)

      assert {:ok, %Module2{created_at: %DateTime{}} = stamped_entity} = create(entity)
      assert DB.get(Module2, entity.id) == stamped_entity
    end

    test "returns an entity carrying no claim" do
      entity =
        Module2
        |> Entity.new()
        |> trust()

      assert {:ok, %Module2{__meta__: %Metadata{claim: nil}}} = create(entity)
    end

    test "skips evaluation for a trust claim and still grants creator roles" do
      user = create_user("creator@example.com")

      entity =
        Module1
        |> Entity.new()
        |> trust()

      assert {:ok, %Module1{}} = as_user(user, fn -> create(entity) end)
      assert granted_roles(user.id, entity.id) == ["maintainer", "owner"]
    end
  end

  describe "delete/1" do
    test "deletes raw without an acting user" do
      entity =
        Module1
        |> Entity.new()
        |> DB.create!()

      assert delete(entity) == :ok
      assert DB.get(Module1, entity.id) == nil
    end

    test "evaluates :delete for the acting user" do
      user = create_user("deleter@example.com")

      parent =
        Module2
        |> Entity.new()
        |> DB.create!()

      entity =
        Module1
        |> Entity.new(parent_id: parent.id)
        |> DB.create!()

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> delete(entity) end)
      end

      assert DB.get(Module1, entity.id) != nil

      # allow :delete, to: {:parent, :admin} - the grant is on the PARENT, not the row.
      Auth.grant_role(user, parent, :admin)

      assert as_user(user, fn -> delete(entity) end) == :ok
      assert DB.get(Module1, entity.id) == nil
    end

    test "evaluates the claim against the row as it stands, not the struct in hand" do
      user = create_user("mover@example.com")

      granting_parent =
        Module2
        |> Entity.new()
        |> DB.create!()

      other_parent =
        Module2
        |> Entity.new()
        |> DB.create!()

      entity =
        Module1
        |> Entity.new(parent_id: granting_parent.id)
        |> DB.create!()

      # allow :delete, to: {:parent, :admin} - the role is granted on the parent the STRUCT
      # names, while the row has since been moved to a parent the user has no role on.
      Auth.grant_role(user, granting_parent, :admin)
      EntityOperations.update(Module1, entity.id, parent_id: other_parent.id)

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> delete(entity) end)
      end

      assert DB.get(Module1, entity.id) != nil
    end

    test "evaluates the operation the entity claims" do
      user = create_user("archiver@example.com")

      entity =
        Module1
        |> Entity.new(author_id: user.id)
        |> DB.create!()

      claimed_entity = authorize(entity, :archive)

      assert as_user(user, fn -> delete(claimed_entity) end) == :ok
      assert DB.get(Module1, entity.id) == nil
    end

    test "skips evaluation for a trust claim" do
      user = create_user("purger@example.com")

      entity =
        Module1
        |> Entity.new()
        |> DB.create!()

      assert as_user(user, fn -> delete(trust(entity)) end) == :ok
      assert DB.get(Module1, entity.id) == nil
    end

    test "is a no-op for an id naming no row, evaluating nothing" do
      user = create_user("ghost@example.com")

      assert delete(Entity.new(Module1)) == :ok
      assert as_user(user, fn -> delete(Entity.new(Module1)) end) == :ok
    end

    test "names the referencer when an incoming reference blocks the delete" do
      source =
        Module16
        |> Entity.new()
        |> DB.create!()

      target =
        Module15
        |> Entity.new(token: "t")
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
      entity =
        Module1
        |> Entity.new()
        |> DB.create!()

      assert delete(Module1, entity.id) == :ok
      assert DB.get(Module1, entity.id) == nil
    end

    test "evaluates :delete for the acting user" do
      user = create_user("id_deleter@example.com")

      parent =
        Module2
        |> Entity.new()
        |> DB.create!()

      entity =
        Module1
        |> Entity.new(parent_id: parent.id)
        |> DB.create!()

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> delete(Module1, entity.id) end)
      end

      assert DB.get(Module1, entity.id) != nil

      Auth.grant_role(user, parent, :admin)

      assert as_user(user, fn -> delete(Module1, entity.id) end) == :ok
      assert DB.get(Module1, entity.id) == nil
    end

    test "is a no-op for an id naming no row" do
      user = create_user("id_ghost@example.com")

      assert as_user(user, fn -> delete(Module1, Entity.generate_id()) end) == :ok
    end
  end

  describe "update/1" do
    test "applies changes and relationship ops under one transaction - a refused value applies no op" do
      source =
        Module16
        |> Entity.new()
        |> DB.create!()

      target =
        Module15
        |> Entity.new(token: "t")
        |> DB.create!()

      entity =
        source
        |> put_attribute(:name, wrap_term(123))
        |> add_relationship(:secrets, target.id)

      assert {:error, %{name: [{:type, :string}]}} = update(entity)
      assert count_edges(source, target) == 0
    end

    test "applies recorded relationship ops in the same transaction" do
      source =
        Module16
        |> Entity.new()
        |> DB.create!()

      target =
        Module15
        |> Entity.new(token: "t")
        |> DB.create!()

      assert source
             |> add_relationship(:secrets, target.id)
             |> update() == :ok

      assert count_edges(source, target) == 1
    end

    test "applies a recorded delete op" do
      source =
        Module16
        |> Entity.new()
        |> DB.create!()

      target =
        Module15
        |> Entity.new(token: "t")
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
        Module1
        |> Entity.new(priority: 5)
        |> DB.create!()

      Auth.grant_role(user, entity, :editor)

      assert as_user(user, fn ->
               entity
               |> put_attribute(:public, true)
               |> update()
             end) == :ok

      # The rule reads the row as it stands, not the struct in hand: the test still holds
      # priority 5 while the row now shows 1, and allow :update wants at least 3.
      EntityOperations.update(Module1, entity.id, priority: 1)

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn ->
          entity
          |> put_attribute(:public, false)
          |> update()
        end)
      end

      assert DB.get(Module1, entity.id).public == true
    end

    test "evaluates the operation the entity claims" do
      user = create_user("archivist@example.com")

      own_entity =
        Module1
        |> Entity.new(author_id: user.id)
        |> DB.create!()

      assert as_user(user, fn ->
               own_entity
               |> put_attribute(:public, true)
               |> authorize(:archive)
               |> update()
             end) == :ok

      other_entity =
        Module1
        |> Entity.new()
        |> DB.create!()

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
        Module1
        |> Entity.new(priority: 5)
        |> DB.create!()

      assert as_user(user, fn ->
               entity
               |> put_attribute(:priority, 9)
               |> trust()
               |> update()
             end) == :ok

      assert DB.get(Module1, entity.id).priority == 9
    end

    test "writes the recorded changes raw without an acting user" do
      entity =
        Module1
        |> Entity.new(priority: 5)
        |> DB.create!()

      assert entity
             |> put_attribute(:priority, 7)
             |> update() == :ok

      reloaded_entity = DB.get(Module1, entity.id)

      assert reloaded_entity.priority == 7
      assert reloaded_entity.public == entity.public
    end

    test "writes a to-one reference field" do
      entity =
        Module1
        |> Entity.new()
        |> DB.create!()

      parent =
        Module2
        |> Entity.new()
        |> DB.create!()

      assert entity
             |> put_attribute(:parent_id, parent.id)
             |> update() == :ok

      assert DB.get(Module1, entity.id).parent_id == parent.id
    end

    test "raises when nothing is recorded" do
      entity =
        Module1
        |> Entity.new()
        |> DB.create!()

      expected_msg =
        "update takes recorded changes - put values with put_attribute and edges with " <>
          "add_relationship or delete_relationship. A field set directly on the struct is " <>
          "not recorded: writing the whole struct would overwrite concurrent changes to " <>
          "fields you didn't touch."

      assert_error ArgumentError, expected_msg, fn -> update(%{entity | public: true}) end
    end

    test "raises when the row does not exist" do
      entity = Entity.new(Module1)

      expected_msg =
        ~s(cannot update Hologram.Test.Fixtures.Policy.Module1 - no entity with id "#{entity.id}")

      assert_error ArgumentError, expected_msg, fn ->
        entity
        |> put_attribute(:public, true)
        |> update()
      end
    end

    test "returns the violation the update validator refuses" do
      entity =
        Module1
        |> Entity.new()
        |> DB.create!()

      assert {:error, %{priority: [{:type, :integer}]}} =
               entity
               |> put_attribute(:priority, wrap_term("x"))
               |> update()
    end
  end

  describe "update/3" do
    test "writes raw without an acting user" do
      entity =
        Module1
        |> Entity.new(priority: 5)
        |> DB.create!()

      assert update(Module1, entity.id, priority: 7) == :ok
      assert DB.get(Module1, entity.id).priority == 7
    end

    test "evaluates :update for the acting user" do
      user = create_user("id_editor@example.com")

      entity =
        Module1
        |> Entity.new(priority: 5)
        |> DB.create!()

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Policy.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(user, fn -> update(Module1, entity.id, public: true) end)
      end

      assert DB.get(Module1, entity.id).public == false

      Auth.grant_role(user, entity, :editor)

      assert as_user(user, fn -> update(Module1, entity.id, public: true) end) == :ok
      assert DB.get(Module1, entity.id).public == true
    end

    test "raises when the row does not exist" do
      user = create_user("id_missing@example.com")
      id = Entity.generate_id()

      expected_msg =
        ~s(cannot update Hologram.Test.Fixtures.Policy.Module1 - no entity with id "#{id}")

      assert_error ArgumentError, expected_msg, fn ->
        as_user(user, fn -> update(Module1, id, public: true) end)
      end
    end
  end
end
