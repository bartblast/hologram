defmodule Hologram.DB.WriterTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.Writer
  import Hologram.Query, only: [authorize: 2, trust: 1]
  import Hologram.Test, only: [as_user: 2]

  alias Hologram.AccessDeniedError
  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module2

  defp create_user(email) do
    Module14
    |> Entity.new(email: email)
    |> DB.create!()
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
end
