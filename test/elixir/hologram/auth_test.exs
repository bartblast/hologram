defmodule Hologram.AuthTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Auth

  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module2
  alias Hologram.Test.Fixtures.Role

  defp create_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  defp create_parent(public \\ false) do
    %{public: public}
    |> Module2.new()
    |> DB.create!()
  end

  defp create_resource do
    DB.create!(Module1.new())
  end

  defp grant_id(user_id) do
    select_sql = ~s|SELECT "id" FROM "hologram_data"."hologram_role_grant" WHERE "user_id" = $1|

    {:ok, %{rows: [[id]]}} = Connection.query(select_sql, [Codec.encode(user_id, :uuid)])

    Codec.decode(id, :uuid)
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

  defp revocation_effects do
    select_sql = """
    SELECT "type", "entity_id"
    FROM "hologram_system"."outbox"
    WHERE "op" = 'del_entity'
    ORDER BY "seq"
    """

    {:ok, %{rows: rows}} = Connection.query(select_sql)

    Enum.map(rows, fn [type, entity_id] -> {type, Codec.decode(entity_id, :uuid)} end)
  end

  # What a check asks is whether a grant EXISTS, so nothing it reads can be gathered - the
  # questions are gathered and answered here, as the session user, so the client's first render
  # can evaluate the same checks against rows rather than waiting for the fill.
  describe "carried_grants/1" do
    test "returns the row answering a check about the session user's own grant" do
      user = create_user("user_80@example.com")
      resource = create_resource()

      grant_role(user, resource, :editor)

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert [%RoleGrant{user_id: grantee_id, resource_id: resource_id}] = rows
      assert grantee_id == user.id
      assert resource_id == resource.id
    end

    test "answers questions about several resources of one type at once" do
      user = create_user("user_81@example.com")
      resource_1 = create_resource()
      resource_2 = create_resource()

      grant_role(user, resource_1, :editor)
      grant_role(user, resource_2, :owner)

      scopes =
        MapSet.new([
          {user.id, {:own, Module1, resource_1.id}},
          {user.id, {:own, Module1, resource_2.id}}
        ])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert length(rows) == 2
    end

    # An own-scope check matches the type-wide row too, which the store keeps apart by a null
    # resource id - so the row answering it has to travel with the rest.
    test "returns the type-wide row an own-scope question also asks about" do
      user = create_user("user_82@example.com")
      resource = create_resource()

      grant_role(user, Module1, :editor)

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert [%RoleGrant{resource_id: nil}] = rows
    end

    test "returns the row answering a global question" do
      user = create_user("user_83@example.com")

      grant_role(user, Role.Module1)

      scopes = MapSet.new([{user.id, :global}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert [%RoleGrant{resource_type: nil, resource_id: nil}] = rows
    end

    test "returns nothing for a question no grant answers" do
      user = create_user("user_84@example.com")
      resource = create_resource()

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      assert Context.with_actor(user.id, fn -> carried_grants(scopes) end) == []
    end

    test "returns nothing when the render asked nothing" do
      user = create_user("user_85@example.com")

      assert Context.with_actor(user.id, fn -> carried_grants(MapSet.new()) end) == []
    end

    # Every grant read rule is actor- or role-shaped, so a visitor holds nothing - the query is
    # skipped rather than run to learn it answers empty.
    test "returns nothing for an anonymous session" do
      user = create_user("user_86@example.com")
      resource = create_resource()

      grant_role(user, resource, :editor)

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      assert carried_grants(scopes) == []
    end

    # The scope says which rows to LOOK FOR, the read policy says which the session user may
    # HOLD - so a question about someone else answers with their row only when the asker's own
    # rules admit it.
    test "withholds another user's row from a session that may not read it" do
      user = create_user("user_87@example.com")
      other_user = create_user("user_88@example.com")
      resource = create_resource()

      grant_role(other_user, resource, :editor)

      scopes = MapSet.new([{other_user.id, {:own, Module1, resource.id}}])

      assert Context.with_actor(user.id, fn -> carried_grants(scopes) end) == []
    end

    test "returns another user's row to a session that may read it" do
      user = create_user("user_89@example.com")
      other_user = create_user("user_90@example.com")
      resource = create_parent()

      grant_role(user, resource, :member)
      grant_role(other_user, resource, :member)

      scopes = MapSet.new([{other_user.id, {:own, Module2, resource.id}}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      # The asker holds a grant on the same resource, so "their row came back" is not the same
      # answer as "only their row did" - the scope named one user and the reply carries one.
      assert [%RoleGrant{user_id: grantee_id, resource_id: resource_id}] = rows
      assert grantee_id == other_user.id
      assert resource_id == resource.id
    end
  end

  describe "can?/3" do
    test "grants an operation through a rule whose predicates hold" do
      assert can?(nil, :read, %Module1{public: true})
    end

    test "denies an operation when no rule matches" do
      refute can?("user_id_1", :read, %Module1{public: false})
    end

    test "denies an operation the entity type declares no rule for" do
      refute can?("user_id_1", :transfer, %Module1{public: true})
    end

    test "matches a rule referencing the acting user" do
      entity = %Module1{author_id: "user_id_2"}

      assert can?("user_id_2", :archive, entity)
      refute can?("user_id_3", :archive, entity)
    end

    test "takes the user entity" do
      user = Module14.new(email: "user_1@example.com")

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

    test "matches a role extending the referenced one" do
      user = create_user("user_44@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, %Module1{id: entity.id}, :owner)

      assert can?(user, :update, entity)
    end

    test "matches a global role module grant" do
      user = create_user("user_45@example.com")
      entity = %Module2{id: Entity.generate_id()}

      refute can?(user, :archive, entity)

      insert_global_grant(user.id, Role.Module1)

      assert can?(user, :archive, entity)
    end

    test "matches a role module extending the referenced one" do
      user = create_user("user_46@example.com")
      entity = %Module2{id: Entity.generate_id()}

      insert_global_grant(user.id, Role.Module2)

      assert can?(user, :archive, entity)
    end

    test "denies a global role module the acting user does not hold" do
      user = create_user("user_47@example.com")
      other_user = create_user("user_48@example.com")

      insert_global_grant(other_user.id, Role.Module1)

      refute can?(user, :archive, %Module2{id: Entity.generate_id()})
    end

    test "skips global role module rules for an anonymous session" do
      refute can?(nil, :archive, %Module2{id: Entity.generate_id()})
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

  describe "can?/3 for the grant store" do
    test "shows a user their own grants" do
      user = create_user("user_50@example.com")

      assert can?(user, :read, %RoleGrant{user_id: user.id})
    end

    test "hides another user's grants without a read-grants role" do
      user = create_user("user_51@example.com")
      other_user = create_user("user_52@example.com")
      resource = create_parent()

      grant = %RoleGrant{
        user_id: other_user.id,
        resource_type: RoleGrant.resource_type(Module2),
        resource_id: resource.id
      }

      refute can?(user, :read, grant)
    end

    test "shows another user's grants to a holder of the resource type's read-grants role" do
      user = create_user("user_53@example.com")
      other_user = create_user("user_54@example.com")
      resource = create_parent()

      grant_role(user, resource, :member)

      grant = %RoleGrant{
        user_id: other_user.id,
        resource_type: RoleGrant.resource_type(Module2),
        resource_id: resource.id
      }

      assert can?(user, :read, grant)
    end

    test "defaults to the roles managing the resource when read_grants is undeclared" do
      owner = create_user("user_55@example.com")
      editor = create_user("user_56@example.com")
      other_user = create_user("user_57@example.com")
      resource = create_resource()

      grant_role(owner, resource, :owner)
      grant_role(editor, resource, :editor)

      grant = %RoleGrant{
        user_id: other_user.id,
        resource_type: RoleGrant.resource_type(Module1),
        resource_id: resource.id
      }

      assert can?(owner, :read, grant)
      refute can?(editor, :read, grant)
    end
  end

  describe "grant_role/2" do
    test "writes a global grant with no resource" do
      user = create_user("user_4@example.com")

      assert grant_role(user, Role.Module1) == :ok

      assert [
               %{
                 resource_type: nil,
                 resource_id: nil,
                 role: "Hologram.Test.Fixtures.Role.Module1"
               }
             ] = grant_rows(user.id)
    end

    test "takes a bare user id" do
      user = create_user("user_5@example.com")

      assert grant_role(user.id, Role.Module1) == :ok

      assert [%{role: "Hologram.Test.Fixtures.Role.Module1"}] = grant_rows(user.id)
    end

    test "keeps the original grant when the user already holds the role" do
      user = create_user("user_49@example.com")

      grant_role(user, Role.Module1)
      [%{created_at: created_at}] = grant_rows(user.id)

      assert grant_role(user, Role.Module1) == :ok

      assert [%{created_at: ^created_at}] = grant_rows(user.id)
    end

    test "raises on a module that is not a global role" do
      user = create_user("user_6@example.com")

      expected_msg =
        "unknown global role Hologram.Test.Fixtures.Entity.Module1 - defined global roles are: Hologram.Test.Fixtures.Role.Module1, Hologram.Test.Fixtures.Role.Module2"

      assert_error ArgumentError, expected_msg, fn ->
        grant_role(user, Hologram.Test.Fixtures.Entity.Module1)
      end
    end

    test "raises on an id that is not a canonical entity id" do
      expected_msg =
        "invalid user id \"nope\" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings"

      assert_error ArgumentError, expected_msg, fn -> grant_role("nope", Role.Module1) end
    end

    test "raises on a user that does not exist" do
      user_id = Entity.generate_id()

      expected_msg =
        "unknown user id #{inspect(user_id)} - roles are granted only to existing users"

      assert_error ArgumentError, expected_msg, fn -> grant_role(user_id, Role.Module1) end
    end

    test "raises on a global grant issued by an acting user" do
      granter = create_user("user_22@example.com")
      user = create_user("user_23@example.com")

      expected_msg =
        "global roles are granted only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, Role.Module1) end)
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
      grant_role(user, Role.Module1)

      assert revoke_role(user, Role.Module1) == :ok
      assert grant_rows(user.id) == []
    end

    # A client watching its own grants learns a row is gone from the round an effect wakes, so a
    # revocation nothing records is one no client hears about until it renders afresh.
    test "records the removal of a global grant" do
      user = create_user("user_51@example.com")
      grant_role(user, Role.Module1)
      revoked_id = grant_id(user.id)

      revoke_role(user, Role.Module1)

      assert revocation_effects() == [{"Hologram.Auth.RoleGrant", revoked_id}]
    end

    test "is a no-op for a role the user does not hold" do
      user = create_user("user_25@example.com")

      assert revoke_role(user, Role.Module1) == :ok
      assert grant_rows(user.id) == []
      assert revocation_effects() == []
    end

    test "raises on a module that is not a global role" do
      user = create_user("user_50@example.com")

      expected_msg =
        "unknown global role Hologram.Test.Fixtures.Entity.Module1 - defined global roles are: Hologram.Test.Fixtures.Role.Module1, Hologram.Test.Fixtures.Role.Module2"

      assert_error ArgumentError, expected_msg, fn ->
        revoke_role(user, Hologram.Test.Fixtures.Entity.Module1)
      end
    end

    test "raises on a global revocation issued by an acting user" do
      granter = create_user("user_26@example.com")
      user = create_user("user_27@example.com")

      expected_msg =
        "global roles are revoked only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> revoke_role(user, Role.Module1) end)
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

    test "records the removal of an instance grant" do
      user = create_user("user_52@example.com")
      resource = create_resource()

      grant_role(user, resource, :owner)
      revoked_id = grant_id(user.id)

      revoke_role(user, resource, :owner)

      assert revocation_effects() == [{"Hologram.Auth.RoleGrant", revoked_id}]
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
