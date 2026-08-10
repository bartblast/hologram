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
  alias Hologram.Test.Fixtures.Policy.Module2

  defp create_user(email) do
    Module14
    |> Entity.new(email: email)
    |> DB.create()
  end

  defp create_parent(public \\ false) do
    Module2
    |> Entity.new(public: public)
    |> DB.create()
  end

  defp create_resource do
    Module1
    |> Entity.new()
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

  describe "authorize!/2" do
    test "returns ok when the session's user may perform the action" do
      user = create_user("user_48@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, %Module1{id: entity.id}, :editor)

      assert Context.with_actor(user.id, fn -> authorize!(:update, entity) end) == :ok
    end

    test "returns ok for an action a rule grants without an acting user" do
      assert authorize!(:read, %Module1{id: Entity.generate_id(), public: true}) == :ok
    end

    test "raises when the session's user may not perform the action" do
      user = create_user("user_49@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      expected_msg =
        "not allowed to perform :update on Hologram.Test.Fixtures.Policy.Module1 " <>
          "#{inspect(entity.id)}"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(user.id, fn -> authorize!(:update, entity) end)
      end
    end

    test "raises for an anonymous session on an action only the acting user may perform" do
      entity = %Module1{id: Entity.generate_id(), author_id: Entity.generate_id()}

      expected_msg =
        "not allowed to perform :archive on Hologram.Test.Fixtures.Policy.Module1 " <>
          "#{inspect(entity.id)}"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        authorize!(:archive, entity)
      end
    end
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

    test "matches an instance grant on the entity" do
      user = create_user("user_41@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      refute can?(user, :update, entity)

      grant_role(user, %Module1{id: entity.id}, :editor)

      assert can?(user, :update, entity)
    end

    test "matches a type-wide grant on the entity type" do
      user = create_user("user_42@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, Module1, :editor)

      assert can?(user, :update, entity)
    end

    test "matches a global grant" do
      user = create_user("user_43@example.com")

      refute can?(user, :update, %Module2{id: Entity.generate_id()})

      grant_role(user, :admin)

      assert can?(user, :update, %Module2{id: Entity.generate_id()})
    end

    test "matches a role extending the referenced one" do
      user = create_user("user_44@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, %Module1{id: entity.id}, :owner)

      assert can?(user, :update, entity)
    end

    test "matches a type-wide grant on another entity type" do
      user = create_user("user_45@example.com")
      entity = %Module1{id: Entity.generate_id()}

      refute can?(user, :read, entity)

      grant_role(user, Module2, :admin)

      assert can?(user, :read, entity)
    end

    test "matches a grant on the entity's related instance" do
      user = create_user("user_46@example.com")
      parent = create_parent()
      entity = %Module1{id: Entity.generate_id(), parent_id: parent.id}

      refute can?(user, :delete, entity)

      grant_role(user, parent, :admin)

      assert can?(user, :delete, entity)
    end

    test "denies a related-instance grant reference on an entity without the reference" do
      user = create_user("user_47@example.com")

      grant_role(user, Module2, :admin)

      refute can?(user, :delete, %Module1{id: Entity.generate_id(), parent_id: nil})
    end

    test "delegates to the related entity's policy" do
      public_parent = create_parent(true)
      private_parent = create_parent()

      assert can?(nil, :publish, %Module1{id: Entity.generate_id(), parent_id: public_parent.id})
      refute can?(nil, :publish, %Module1{id: Entity.generate_id(), parent_id: private_parent.id})
    end

    test "denies delegation without the reference" do
      refute can?(nil, :publish, %Module1{id: Entity.generate_id(), parent_id: nil})
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

    test "raises on a global grant issued by an acting user" do
      granter = create_user("user_22@example.com")
      user = create_user("user_23@example.com")

      expected_msg =
        "global roles are granted only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, :admin) end)
      end
    end
  end

  describe "grant_role/3" do
    test "writes an instance grant naming the resource type and id" do
      user = create_user("user_7@example.com")

      resource = create_resource()

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

      resource = create_resource()

      grant_role(granter, resource, :owner)

      Context.with_actor(granter.id, fn -> grant_role(user, resource, :editor) end)

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

      resource = create_resource()

      grant_role(granter, resource, :owner)

      Context.with_actor(granter.id, fn -> grant_role(user, resource, :editor) end)
      [original_grant] = grant_rows(user.id)

      assert grant_role(user, resource, :editor) == :ok

      assert grant_rows(user.id) == [original_grant]
    end

    test "grants when the acting user manages the resource's roles" do
      granter = create_user("user_16@example.com")
      user = create_user("user_17@example.com")

      resource = create_resource()

      grant_role(granter, resource, :owner)

      assert Context.with_actor(granter.id, fn -> grant_role(user, resource, :editor) end) == :ok

      assert [%{role: "editor"}] = grant_rows(user.id)
    end

    test "raises when the acting user does not manage the resource's roles" do
      granter = create_user("user_18@example.com")
      user = create_user("user_19@example.com")

      resource = create_resource()

      grant_role(granter, resource, :editor)

      expected_msg =
        "not allowed to manage the roles of Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, resource, :editor) end)
      end
    end

    test "raises on a type-wide grant issued by an acting user" do
      granter = create_user("user_20@example.com")
      user = create_user("user_21@example.com")

      expected_msg =
        "type-wide roles are granted only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, Module1, :owner) end)
      end
    end

    test "raises on a role the resource type does not declare" do
      user = create_user("user_14@example.com")

      expected_msg =
        "unknown role :publisher for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

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

  describe "revoke_role/2" do
    test "removes a global grant" do
      user = create_user("user_24@example.com")
      grant_role(user, :admin)

      assert revoke_role(user, :admin) == :ok
      assert grant_rows(user.id) == []
    end

    test "is a no-op for a role the user does not hold" do
      user = create_user("user_25@example.com")

      assert revoke_role(user, :admin) == :ok
      assert grant_rows(user.id) == []
    end

    test "raises on a global revocation issued by an acting user" do
      granter = create_user("user_26@example.com")
      user = create_user("user_27@example.com")

      expected_msg =
        "global roles are revoked only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> revoke_role(user, :admin) end)
      end
    end
  end

  describe "revoke_role/3" do
    test "removes an instance grant" do
      user = create_user("user_28@example.com")
      resource = create_resource()

      grant_role(user, resource, :owner)

      assert revoke_role(user, resource, :owner) == :ok
      assert grant_rows(user.id) == []
    end

    test "lets a user revoke their own role" do
      owner = create_user("user_29@example.com")
      member = create_user("user_30@example.com")
      resource = create_resource()

      grant_role(owner, resource, :owner)
      grant_role(member, resource, :editor)

      assert Context.with_actor(member.id, fn -> revoke_role(member, resource, :editor) end) ==
               :ok

      assert grant_rows(member.id) == []
    end

    test "removes another user's role when the acting user manages the resource" do
      owner = create_user("user_31@example.com")
      member = create_user("user_32@example.com")
      resource = create_resource()

      grant_role(owner, resource, :owner)
      grant_role(member, resource, :editor)

      assert Context.with_actor(owner.id, fn -> revoke_role(member, resource, :editor) end) == :ok

      assert grant_rows(member.id) == []
    end

    test "raises when the acting user neither owns the role nor manages the resource" do
      member = create_user("user_33@example.com")
      other_member = create_user("user_34@example.com")
      resource = create_resource()

      grant_role(member, resource, :editor)
      grant_role(other_member, resource, :editor)

      expected_msg =
        "not allowed to manage the roles of Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(other_member.id, fn -> revoke_role(member, resource, :editor) end)
      end
    end

    test "refuses to revoke the last role managing the resource" do
      owner = create_user("user_35@example.com")
      resource = create_resource()

      grant_role(owner, resource, :owner)

      expected_msg =
        "cannot revoke the last role managing Hologram.Test.Fixtures.Policy.Module1 " <>
          "#{inspect(resource.id)} - transfer ownership first"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(owner.id, fn -> revoke_role(owner, resource, :owner) end)
      end
    end

    test "revokes a managing role while another one remains" do
      first_owner = create_user("user_36@example.com")
      second_owner = create_user("user_37@example.com")
      resource = create_resource()

      grant_role(first_owner, resource, :owner)
      grant_role(second_owner, resource, :owner)

      assert Context.with_actor(first_owner.id, fn ->
               revoke_role(first_owner, resource, :owner)
             end) == :ok

      assert grant_rows(first_owner.id) == []
    end

    test "revokes the last managing role for trusted code" do
      owner = create_user("user_38@example.com")
      resource = create_resource()

      grant_role(owner, resource, :owner)

      assert revoke_role(owner, resource, :owner) == :ok
      assert grant_rows(owner.id) == []
    end

    test "raises on a type-wide revocation issued by an acting user" do
      granter = create_user("user_39@example.com")
      user = create_user("user_40@example.com")

      expected_msg =
        "type-wide roles are revoked only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> revoke_role(user, Module1, :owner) end)
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
