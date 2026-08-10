defmodule Hologram.AuthTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Auth

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1

  defp create_user(email) do
    Module14
    |> Entity.new(email: email)
    |> DB.create()
  end

  defp grant_rows(user_id) do
    select_sql =
      ~s|SELECT "resource_type", "resource_id", "role", "granted_by_id", "created_at" | <>
        ~s|FROM "hologram_data"."hologram_role_grant" WHERE "user_id" = $1|

    {:ok, %{rows: rows}} = Connection.query(select_sql, [Codec.encode(user_id, :uuid)])

    Enum.map(rows, fn [resource_type, resource_id, role, granted_by_id, created_at] ->
      %{
        created_at: created_at,
        granted_by_id: granted_by_id && Codec.decode(granted_by_id, :uuid),
        resource_id: resource_id && Codec.decode(resource_id, :uuid),
        resource_type: resource_type,
        role: role
      }
    end)
  end

  describe "can?/3" do
    test "grants an action through a rule whose predicates hold" do
      assert can?(nil, :read, %Module1{public: true})
    end

    test "denies an action when no rule matches" do
      refute can?("user_id_1", :read, %Module1{public: false})
    end

    test "denies an action the entity type declares no rule for" do
      refute can?("user_id_1", :transfer, %Module1{public: true})
    end

    test "matches a rule referencing the acting user" do
      entity = %Module1{author_id: "user_id_2"}

      assert can?("user_id_2", :archive, entity)
      refute can?("user_id_3", :archive, entity)
    end

    test "takes the user entity" do
      user = Entity.new(Module14, email: "user_1@example.com")

      assert can?(user, :archive, %Module1{author_id: user.id})
    end

    test "skips rules referencing the acting user for an anonymous session" do
      refute can?(nil, :archive, %Module1{author_id: nil})
    end
  end

  describe "grant_role/2" do
    test "writes a global grant with no resource" do
      user = create_user("user_4@example.com")

      assert grant_role(user, :admin) == :ok

      assert [%{resource_type: nil, resource_id: nil, role: "admin"}] = grant_rows(user.id)
    end

    test "takes a bare user id" do
      user = create_user("user_5@example.com")

      assert grant_role(user.id, :admin) == :ok

      assert [%{role: "admin"}] = grant_rows(user.id)
    end

    test "raises on a role declared without global scope" do
      user = create_user("user_6@example.com")

      expected_msg = "unknown global role :editor - declared global roles are: :admin"

      assert_error ArgumentError, expected_msg, fn -> grant_role(user, :editor) end
    end

    test "raises on an id that is not a canonical entity id" do
      expected_msg =
        "invalid user id \"nope\" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings"

      assert_error ArgumentError, expected_msg, fn -> grant_role("nope", :admin) end
    end

    test "raises on a user that does not exist" do
      user_id = Entity.generate_id()

      expected_msg =
        "unknown user id #{inspect(user_id)} - roles are granted only to existing users"

      assert_error ArgumentError, expected_msg, fn -> grant_role(user_id, :admin) end
    end
  end

  describe "grant_role/3" do
    test "writes an instance grant naming the resource type and id" do
      user = create_user("user_7@example.com")

      resource =
        Module1
        |> Entity.new()
        |> DB.create()

      assert grant_role(user, resource, :owner) == :ok

      assert [%{resource_type: "test_fixtures_policy_module1", role: "owner"} = grant] =
               grant_rows(user.id)

      assert grant.resource_id == resource.id
    end

    test "writes a type-wide grant with no resource id" do
      user = create_user("user_8@example.com")

      assert grant_role(user, Module1, :owner) == :ok

      assert [%{resource_type: "test_fixtures_policy_module1", resource_id: nil, role: "owner"}] =
               grant_rows(user.id)
    end

    test "stamps the acting user as the granter" do
      granter = create_user("user_9@example.com")
      user = create_user("user_10@example.com")

      Context.with_actor(granter.id, fn -> grant_role(user, Module1, :owner) end)

      assert [%{granted_by_id: granted_by_id}] = grant_rows(user.id)
      assert granted_by_id == granter.id
    end

    test "leaves the granter unset outside an actor context" do
      user = create_user("user_11@example.com")

      grant_role(user, Module1, :owner)

      assert [%{granted_by_id: nil}] = grant_rows(user.id)
    end

    test "keeps the original grant when the role is already held" do
      granter = create_user("user_12@example.com")
      user = create_user("user_13@example.com")

      Context.with_actor(granter.id, fn -> grant_role(user, Module1, :owner) end)
      [original_grant] = grant_rows(user.id)

      assert grant_role(user, Module1, :owner) == :ok

      assert grant_rows(user.id) == [original_grant]
    end

    test "raises on a role the resource type does not declare" do
      user = create_user("user_14@example.com")

      expected_msg =
        "unknown role :publisher for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :owner, :viewer"

      assert_error ArgumentError, expected_msg, fn -> grant_role(user, Module1, :publisher) end
    end

    test "raises on a resource id that is not a canonical entity id" do
      user = create_user("user_15@example.com")

      expected_msg =
        "invalid resource id \"nope\" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings"

      assert_error ArgumentError, expected_msg, fn ->
        grant_role(user, %Module1{id: "nope"}, :owner)
      end
    end
  end

  describe "user_id/0" do
    test "returns the actor of the calling process" do
      assert Context.with_actor("user_id_1", fn -> user_id() end) == "user_id_1"
    end

    test "returns nil for an anonymous session" do
      assert user_id() == nil
    end
  end
end
