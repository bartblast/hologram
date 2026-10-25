defmodule Hologram.AuthTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Auth

  require Hologram.Query

  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Sync.Carry
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module10
  alias Hologram.Test.Fixtures.Policy.Module11
  alias Hologram.Test.Fixtures.Policy.Module12
  alias Hologram.Test.Fixtures.Policy.Module2
  alias Hologram.Test.Fixtures.Policy.Module4
  alias Hologram.Test.Fixtures.Policy.Module5
  alias Hologram.Test.Fixtures.Policy.Module8
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

  # A Module5 row whose parent is a Module1 row with the given parent - the row two hops away from
  # a Module12 row pointing at the Module5 row is the Module1 row.
  defp create_path_rows(parent_id) do
    resource =
      %{parent_id: parent_id}
      |> Module1.new()
      |> DB.create!()

    middle =
      %{parent_id: resource.id}
      |> Module5.new()
      |> DB.create!()

    {resource, middle}
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
      ~s|SELECT "entity_type", "entity_id", "role", "granted_by_id", "created_at" | <>
        ~s|FROM "hologram_data"."hologram_role_grant" WHERE "user_id" = $1|

    {:ok, %{rows: rows}} = Connection.query(select_sql, [Codec.encode(user_id, :uuid)])

    Enum.map(rows, fn [entity_type, entity_id, role, granted_by_id, created_at] ->
      %{
        created_at: created_at,
        granted_by_id: granted_by_id && Codec.decode(granted_by_id, :uuid),
        entity_id: entity_id && Codec.decode(entity_id, :uuid),
        entity_type: entity_type,
        role: role
      }
    end)
  end

  # The row a batch's grant write arrives as - what Hologram.Mutation.Write.to_entity/1 hands the
  # applier, with the granter already taken from the acting user.
  defp grant_struct(opts) do
    entity_id = Keyword.get(opts, :entity_id)
    entity_type = Keyword.get(opts, :entity_type)
    role = Keyword.fetch!(opts, :role)
    user_id = Keyword.fetch!(opts, :user_id)

    %RoleGrant{
      entity_id: entity_id,
      entity_type: entity_type,
      granted_by_id: Keyword.get(opts, :granted_by_id),
      id: RoleGrant.derive_id(user_id, entity_type, entity_id, role),
      role: role,
      user_id: user_id
    }
  end

  defp revocation_effects do
    select_sql = """
    SELECT "type", "entity_id"
    FROM "hologram_system"."oplog"
    WHERE "op" = 'del_entity'
    ORDER BY "seq"
    """

    {:ok, %{rows: rows}} = Connection.query(select_sql)

    Enum.map(rows, fn [type, entity_id] -> {type, Codec.decode(entity_id, :uuid)} end)
  end

  # The row apply_revocation_write/2 is handed - read back from the store by id, the way the applier
  # reads it, rather than built: a revocation is judged against the grant as it was made. Read raw,
  # because the store's own read policy would withhold it from a test running with no actor.
  defp held_grant(user_id) do
    EntityOperations.get(RoleGrant, grant_id(user_id))
  end

  # What a check asks is whether a grant EXISTS, so nothing it reads can be gathered - the
  # questions are gathered and answered here, as the session user, so the client's first render
  # can evaluate the same checks against rows rather than waiting for the fill.
  describe "carried_grants/1" do
    test "returns the row answering a check about the session user's own grant" do
      user = create_user("user_80@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert [%RoleGrant{user_id: grantee_id, entity_id: entity_id}] = rows
      assert grantee_id == user.id
      assert entity_id == resource.id
    end

    test "answers questions about several resources of one type at once" do
      user = create_user("user_81@example.com")
      resource_1 = create_resource()
      resource_2 = create_resource()

      grant_role(user, :editor, resource_1)
      grant_role(user, :owner, resource_2)

      scopes =
        MapSet.new([
          {user.id, {:own, Module1, resource_1.id}},
          {user.id, {:own, Module1, resource_2.id}}
        ])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert length(rows) == 2
    end

    # An own-scope check matches the type-wide row too, which the store keeps apart by a null
    # entity id - so the row answering it has to travel with the rest.
    test "returns the type-wide row an own-scope question also asks about" do
      user = create_user("user_82@example.com")
      resource = create_resource()

      grant_role(user, :editor, Module1)

      scopes = MapSet.new([{user.id, {:own, Module1, resource.id}}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert [%RoleGrant{entity_id: nil}] = rows
    end

    test "returns the row answering a global question" do
      user = create_user("user_83@example.com")

      grant_role(user, Role.Module1)

      scopes = MapSet.new([{user.id, :global}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      assert [%RoleGrant{entity_type: nil, entity_id: nil}] = rows
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

      grant_role(user, :editor, resource)

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

      grant_role(other_user, :editor, resource)

      scopes = MapSet.new([{other_user.id, {:own, Module1, resource.id}}])

      assert Context.with_actor(user.id, fn -> carried_grants(scopes) end) == []
    end

    test "returns another user's row to a session that may read it" do
      user = create_user("user_89@example.com")
      other_user = create_user("user_90@example.com")
      resource = create_parent()

      grant_role(user, :member, resource)
      grant_role(other_user, :member, resource)

      scopes = MapSet.new([{other_user.id, {:own, Module2, resource.id}}])

      rows = Context.with_actor(user.id, fn -> carried_grants(scopes) end)

      # The asker holds a grant on the same resource, so "their row came back" is not the same
      # answer as "only their row did" - the scope named one user and the reply carries one.
      assert [%RoleGrant{user_id: grantee_id, entity_id: entity_id}] = rows
      assert grantee_id == other_user.id
      assert entity_id == resource.id
    end
  end

  describe "can?/3" do
    test "grants an operation through a rule whose predicates hold" do
      assert can?(nil, :read, %Module1{public: true})
    end

    test "denies an operation when no rule matches" do
      refute can?("user_id_1", :read, %Module1{public: false})
    end

    test "denies a framework operation the entity type declares no rule for" do
      refute can?("user_id_1", :create, %Module1{public: true})
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

      grant_role(user, :editor, %Module1{id: entity.id})

      assert can?(user, :update, entity)
    end

    test "matches a type-wide grant on the entity type" do
      user = create_user("user_42@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, :editor, Module1)

      assert can?(user, :update, entity)
    end

    test "matches a role extending the referenced one" do
      user = create_user("user_44@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, :owner, %Module1{id: entity.id})

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

      grant_role(user, :admin, Module2)

      assert can?(user, :read, entity)
    end

    test "matches a grant on the entity's related instance" do
      user = create_user("user_46@example.com")
      parent = create_parent()
      entity = %Module1{id: Entity.generate_id(), parent_id: parent.id}

      refute can?(user, :delete, entity)

      grant_role(user, :admin, parent)

      assert can?(user, :delete, entity)
    end

    test "denies a related-instance grant reference on an entity without the reference" do
      user = create_user("user_47@example.com")

      grant_role(user, :admin, Module2)

      refute can?(user, :delete, %Module1{id: Entity.generate_id(), parent_id: nil})
    end

    test "matches a grant on the row a path ends at" do
      user = create_user("user_161@example.com")
      {resource, middle} = create_path_rows(nil)
      entity = %Module12{id: Entity.generate_id(), parent_id: middle.id}

      refute can?(user, :update, entity)

      grant_role(user, :viewer, resource)

      assert can?(user, :update, entity)
    end

    test "denies a grant reference whose path ends nowhere" do
      user = create_user("user_162@example.com")
      middle = DB.create!(Module5.new())

      grant_role(user, :viewer, Module1)

      refute can?(user, :update, %Module12{id: Entity.generate_id(), parent_id: middle.id})
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

    test "delegates through a path" do
      public_parent = create_parent(true)
      private_parent = create_parent()
      {_resource, public_middle} = create_path_rows(public_parent.id)
      {_resource, private_middle} = create_path_rows(private_parent.id)

      assert can?(nil, :publish, %Module12{id: Entity.generate_id(), parent_id: public_middle.id})

      refute can?(nil, :publish, %Module12{id: Entity.generate_id(), parent_id: private_middle.id})
    end

    test "denies a delegation whose path ends nowhere" do
      middle = DB.create!(Module5.new())

      refute can?(nil, :publish, %Module12{id: Entity.generate_id(), parent_id: middle.id})
    end

    test "reads the rows along a path without a lock" do
      parent = create_parent(true)
      {_resource, middle} = create_path_rows(parent.id)

      assert can?(nil, :publish, %Module12{id: Entity.generate_id(), parent_id: middle.id})

      refute "RowShareLock" in relation_lock_modes(Module5)
    end

    # A render's question takes no lock - a lock held from a render would make every page load a
    # lock holder.
    test "reads the related row a delegation reads without a lock" do
      parent = create_parent(true)

      assert can?(nil, :publish, %Module1{id: Entity.generate_id(), parent_id: parent.id})

      refute "RowShareLock" in relation_lock_modes(Module2)
    end

    # The related type's create rule is open, so the refusal before the grant pins that the delegation
    # asks the parent's update rule instead.
    test "grants through the operation a delegation names" do
      user = create_user("user_158@example.com")
      parent = DB.create!(Module10.new())
      entity = %Module11{id: Entity.generate_id(), parent_id: parent.id}

      refute can?(user, :create, entity)

      grant_role(user, :editor, parent)

      assert can?(user, :create, entity)
    end

    test "denies when the operation a delegation names denies" do
      user = create_user("user_159@example.com")

      parent =
        %{archived: true}
        |> Module10.new()
        |> DB.create!()

      grant_role(user, :editor, parent)

      refute can?(user, :create, %Module11{id: Entity.generate_id(), parent_id: parent.id})
    end

    test "answers a grant lifecycle operation for one role" do
      owner = create_user("user_58@example.com")
      editor = create_user("user_59@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      assert can?(owner, {:grant_role, :editor}, resource)
      refute can?(editor, {:grant_role, :editor}, resource)
    end

    test "answers the bare grant lifecycle operation for any role" do
      owner = create_user("user_60@example.com")
      editor = create_user("user_61@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      assert can?(owner, :grant_role, resource)
      refute can?(editor, :grant_role, resource)
    end

    test "raises on a grant lifecycle operation naming several roles" do
      user = create_user("user_62@example.com")
      resource = create_resource()

      expected_msg = "can? asks about one role - {:grant_role, [:editor, :viewer]} names several"

      assert_error ArgumentError, expected_msg, fn ->
        can?(user, {:grant_role, [:editor, :viewer]}, resource)
      end
    end

    # IMPORTANT!
    # The shape message is the client's, pinned there by "raises on an operation that is neither an
    # atom nor a role tuple" in test/javascript/elixir/hologram/auth_test.mjs. Always update both.
    test "raises on a role tuple whose members are not atoms" do
      expected_msg =
        "can? takes an operation atom or a {:grant_role, role} / {:revoke_role, role} tuple"

      assert_error ArgumentError, expected_msg, fn ->
        can?("user_id_1", {:grant_role, "viewer"}, %Module1{public: true})
      end
    end

    test "raises on a tuple that is not a pair" do
      expected_msg =
        "can? takes an operation atom or a {:grant_role, role} / {:revoke_role, role} tuple"

      assert_error ArgumentError, expected_msg, fn ->
        can?("user_id_1", {:grant_role, :editor, :extra}, %Module1{public: true})
      end
    end

    test "raises on an operation that is neither an atom nor a tuple" do
      expected_msg =
        "can? takes an operation atom or a {:grant_role, role} / {:revoke_role, role} tuple"

      assert_error ArgumentError, expected_msg, fn ->
        can?("user_id_1", "read", %Module1{public: true})
      end
    end

    test "raises on an operation the entity type declares no rule for" do
      expected_msg =
        "unknown operation :transfer for Hologram.Test.Fixtures.Policy.Module1 - its allow lines declare :archive and :publish, and the framework's own operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update"

      assert_error ArgumentError, expected_msg, fn ->
        can?("user_id_1", :transfer, %Module1{public: true})
      end
    end

    test "raises on a tuple whose name is not a grant lifecycle operation" do
      expected_msg =
        "unknown operation {:publish, :editor} for Hologram.Test.Fixtures.Policy.Module1 - the operation tuples are {:grant_role, role} and {:revoke_role, role}"

      assert_error ArgumentError, expected_msg, fn ->
        can?("user_id_1", {:publish, :editor}, %Module1{public: true})
      end
    end

    test "raises on a grant lifecycle operation naming a role the entity type does not declare" do
      expected_msg =
        "unknown role :editr in {:grant_role, :editr} for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error ArgumentError, expected_msg, fn ->
        can?("user_id_1", {:grant_role, :editr}, %Module1{public: true})
      end
    end
  end

  describe "can?/3 for the grant store" do
    test "shows a user their own grants" do
      user = create_user("user_50@example.com")

      assert can?(user, :read, %RoleGrant{user_id: user.id})
    end

    test "hides another user's grants without a read-roles role" do
      user = create_user("user_51@example.com")
      other_user = create_user("user_52@example.com")
      resource = create_parent()

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      refute can?(user, :read, grant)
    end

    test "shows another user's grants to a holder of the resource type's read-roles role" do
      user = create_user("user_53@example.com")
      other_user = create_user("user_54@example.com")
      resource = create_parent()

      grant_role(user, :member, resource)

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      assert can?(user, :read, grant)
    end

    test "shows another user's grants to a holder of a role that may grant on the resource" do
      admin = create_user("user_63@example.com")
      other_user = create_user("user_64@example.com")
      resource = create_parent()

      grant_role(admin, :admin, resource)

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      assert can?(admin, :read, grant)
    end

    test "shows another user's grants to a holder of a global role that may grant on the resource" do
      global_holder = create_user("user_88@example.com")
      other_user = create_user("user_89@example.com")
      resource = create_parent()

      grant_role(global_holder, Role.Module1)

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      assert can?(global_holder, :read, grant)
    end

    test "defaults to the roles that may grant or revoke when read_roles is undeclared" do
      owner = create_user("user_55@example.com")
      editor = create_user("user_56@example.com")
      other_user = create_user("user_57@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module1,
        entity_id: resource.id
      }

      assert can?(owner, :read, grant)
      refute can?(editor, :read, grant)
    end
  end

  describe "can?/4" do
    test "answers from the given grants rather than the stored ones" do
      user = create_user("user_60@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module1,
        entity_id: entity.id,
        role: :viewer
      }

      refute can?(user, :read, entity)
      assert can?(user, :read, entity, [grant])
    end

    test "denies what the given grants do not hold though the store does" do
      user = create_user("user_61@example.com")
      entity = create_resource()

      grant_role(user, :viewer, entity)

      assert can?(user, :read, entity)
      refute can?(user, :read, entity, [])
    end

    test "matches a global grant" do
      user = create_user("user_62@example.com")
      entity = %Module2{id: Entity.generate_id()}

      grant = %RoleGrant{user_id: user.id, role: Role.Module1}

      assert can?(user, :archive, entity, [grant])
    end

    test "matches a type-wide grant" do
      user = create_user("user_63@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module2,
        role: :admin
      }

      assert can?(user, :read, entity, [grant])
    end

    # An own-scope check admits the row's grant AND the type-wide one, which the store's own
    # condition spells as "entity_id = $3 OR entity_id IS NULL".
    test "matches a type-wide grant of the row's own type" do
      user = create_user("user_72@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module1,
        role: :viewer
      }

      assert can?(user, :read, entity, [grant])
    end

    test "matches a grant on the row itself" do
      user = create_user("user_64@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module1,
        entity_id: entity.id,
        role: :editor
      }

      assert can?(user, :update, entity, [grant])
    end

    test "matches a grant on a related row" do
      user = create_user("user_65@example.com")
      parent = %Module2{id: Entity.generate_id()}
      entity = %Module1{id: Entity.generate_id(), parent_id: parent.id}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module2,
        entity_id: parent.id,
        role: :admin
      }

      assert can?(user, :delete, entity, [grant])
    end

    # A delegation asks the RELATED row's policy, so the list has to reach that far too - a
    # fallback to the store there would judge half the policy under grants nobody asked about.
    test "matches a grant through a delegation" do
      user = create_user("user_66@example.com")
      parent = create_parent()
      entity = %Module4{id: Entity.generate_id(), parent_id: parent.id}

      grant = %RoleGrant{user_id: user.id, role: Role.Module1}

      refute can?(user, :archive, entity)
      assert can?(user, :archive, entity, [grant])
    end

    test "reads the related row a delegation reads without a lock" do
      user = create_user("user_157@example.com")
      parent = create_parent()
      grant = %RoleGrant{user_id: user.id, role: Role.Module1}

      assert can?(user, :archive, %Module4{id: Entity.generate_id(), parent_id: parent.id}, [
               grant
             ])

      refute "RowShareLock" in relation_lock_modes(Module2)
    end

    test "matches a grant for the grant store's own rows" do
      user = create_user("user_67@example.com")
      other_user = create_user("user_68@example.com")
      resource = create_parent()

      row = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module2,
        entity_id: resource.id,
        role: :member
      }

      refute can?(user, :read, row, [])
      assert can?(user, :read, row, [grant])
    end

    test "denies a grant held by somebody else" do
      user = create_user("user_69@example.com")
      other_user = create_user("user_70@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module1,
        entity_id: entity.id,
        role: :viewer
      }

      refute can?(user, :read, entity, [grant])
    end

    # A check answered from a list is nobody's question, so a render gathers nothing from it -
    # where the stored check records the scope so the answering row can travel with the page.
    test "records nothing for a render to carry" do
      user = create_user("user_71@example.com")
      entity = %Module1{id: Entity.generate_id()}

      grant = %RoleGrant{
        user_id: user.id,
        entity_type: Module1,
        entity_id: entity.id,
        role: :viewer
      }

      Carry.start()
      assert can?(user, :read, entity, [grant])
      assert Carry.take_grant_scopes() == MapSet.new()

      Carry.start()
      refute can?(user, :read, entity)
      # Both of the type's read rules reference a grant, and a stored check records every one it
      # asks - which is what a render needs to carry the rows answering them.
      assert Carry.take_grant_scopes() ==
               MapSet.new([
                 {user.id, {:own, Module1, entity.id}},
                 {user.id, {:type, Module2}}
               ])
    end

    # What :held holds is only visible across sessions - the scratch tier pins that. Here, that it
    # answers what the store answers, for every rule kind.
    test "with :held answers from the store" do
      user = create_user("user_146@example.com")
      other_user = create_user("user_147@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, :editor, %Module1{id: entity.id})

      assert can?(user, :update, entity, :held)
      refute can?(other_user, :update, entity, :held)
    end

    test "with :held matches a type-wide grant" do
      user = create_user("user_148@example.com")
      entity = %Module1{id: Entity.generate_id(), priority: 5}

      grant_role(user, :editor, Module1)

      assert can?(user, :update, entity, :held)
    end

    test "with :held matches a type-wide grant on another entity type" do
      user = create_user("user_152@example.com")

      grant_role(user, :admin, Module2)

      assert can?(user, :read, %Module1{id: Entity.generate_id()}, :held)
    end

    test "with :held matches a global role module grant" do
      user = create_user("user_149@example.com")
      entity = %Module2{id: Entity.generate_id()}

      insert_global_grant(user.id, Role.Module1)

      assert can?(user, :archive, entity, :held)
    end

    test "with :held matches a grant on a related row" do
      user = create_user("user_150@example.com")
      parent = create_parent()

      grant_role(user, :admin, parent)

      assert can?(user, :delete, %Module1{id: Entity.generate_id(), parent_id: parent.id}, :held)
      refute can?(user, :delete, %Module1{id: Entity.generate_id(), parent_id: nil}, :held)
    end

    test "with :held follows a delegation" do
      user = create_user("user_151@example.com")
      parent = create_parent()
      entity = %Module4{id: Entity.generate_id(), parent_id: parent.id}

      refute can?(user, :archive, entity, :held)

      insert_global_grant(user.id, Role.Module1)

      assert can?(user, :archive, entity, :held)
    end

    # A locking read shows in pg_locks as RowShareLock on the relation, even uncontended - the row
    # lock itself, and which mode it is, only the scratch tier sees. Each test is its own sandbox
    # transaction, so a lock one takes is not there in the next.
    test "with :held holds the related row a delegation reads" do
      user = create_user("user_155@example.com")
      parent = create_parent()

      # The answer is false - Module2's :archive wants a global role the user does not hold - and
      # beside the point: the parent row is read before any grant is asked.
      can?(user, :archive, %Module4{id: Entity.generate_id(), parent_id: parent.id}, :held)

      assert "RowShareLock" in relation_lock_modes(Module2)
    end

    # The chain's end row is not asserted: the middle row's insert ran its foreign key check, which
    # already holds RowShareLock on the end row's table. The scratch tier proves the far hop.
    test "with :held holds the first related row of a delegation chain" do
      user = create_user("user_156@example.com")

      resource =
        %{public: true}
        |> Module1.new()
        |> DB.create!()

      middle =
        %{parent_id: resource.id}
        |> Module5.new()
        |> DB.create!()

      assert can?(user, :read, %Module8{id: Entity.generate_id(), parent_id: middle.id}, :held)

      assert "RowShareLock" in relation_lock_modes(Module5)
    end

    # The answer is false - the user is no editor of the parent - and it would be true if the
    # delegation asked the parent's open create rule.
    test "with :held holds the related row a delegation naming its operation reads" do
      user = create_user("user_160@example.com")
      parent = DB.create!(Module10.new())

      refute can?(user, :create, %Module11{id: Entity.generate_id(), parent_id: parent.id}, :held)

      assert "RowShareLock" in relation_lock_modes(Module10)
    end

    # As for a chain of delegations, only the first row is asserted: the inserts of the rows past it
    # already hold RowShareLock on their tables through their foreign key checks.
    test "with :held holds the first row a delegation path reads" do
      parent = create_parent(true)
      {_resource, middle} = create_path_rows(parent.id)
      entity = %Module12{id: Entity.generate_id(), parent_id: middle.id}

      assert can?(create_user("user_163@example.com"), :publish, entity, :held)

      assert "RowShareLock" in relation_lock_modes(Module5)
    end

    test "with :held holds the row a grant reference path reads on its way" do
      user = create_user("user_164@example.com")
      {resource, middle} = create_path_rows(nil)

      grant_role(user, :viewer, resource)

      assert can?(user, :update, %Module12{id: Entity.generate_id(), parent_id: middle.id}, :held)

      assert "RowShareLock" in relation_lock_modes(Module5)
    end

    test "with :held matches a grant for the grant store's own rows" do
      user = create_user("user_153@example.com")
      other_user = create_user("user_154@example.com")
      resource = create_parent()

      row = %RoleGrant{
        user_id: other_user.id,
        entity_type: Module2,
        entity_id: resource.id
      }

      refute can?(user, :read, row, :held)

      grant_role(user, :member, resource)

      assert can?(user, :read, row, :held)
    end

    test "with :held answers false for an anonymous session" do
      refute can?(nil, :update, %Module1{id: Entity.generate_id(), priority: 5}, :held)
    end
  end

  describe "chain_target_id/3" do
    test "answers nil for a hop naming a row that is gone" do
      entity = %Module5{parent_id: Entity.generate_id()}

      assert chain_target_id(entity, [:parent, :parent]) == nil
    end

    test "answers nil for an empty hop" do
      assert chain_target_id(%Module5{parent_id: nil}, [:parent]) == nil
    end

    test "answers nil for an empty hop later in the chain" do
      middle = DB.create!(Module1.new())

      assert chain_target_id(%Module5{parent_id: middle.id}, [:parent, :parent]) == nil
    end

    test "answers the id one hop away" do
      target_id = Entity.generate_id()

      assert chain_target_id(%Module5{parent_id: target_id}, [:parent]) == target_id
    end

    test "follows a chain through stored rows" do
      target = create_parent()

      middle =
        %{parent_id: target.id}
        |> Module1.new()
        |> DB.create!()

      assert chain_target_id(%Module5{parent_id: middle.id}, [:parent, :parent]) == target.id
    end

    # The chain's end row is not read: its id is the middle row's reference.
    test "reads the rows along the chain with the given options" do
      target = create_parent()

      middle =
        %{parent_id: target.id}
        |> Module1.new()
        |> DB.create!()

      entity = %Module5{parent_id: middle.id}

      assert chain_target_id(entity, [:parent, :parent], lock: :share) == target.id

      assert "RowShareLock" in relation_lock_modes(Module1)
    end

    test "reads the rows along the chain unlocked by default" do
      target = create_parent()

      middle =
        %{parent_id: target.id}
        |> Module1.new()
        |> DB.create!()

      assert chain_target_id(%Module5{parent_id: middle.id}, [:parent, :parent]) == target.id

      refute "RowShareLock" in relation_lock_modes(Module1)
    end
  end

  describe "grants_before/2" do
    defp grant_effect(op, grant) do
      data = %{
        "id" => grant.id,
        "entity_id" => grant.entity_id,
        "entity_type" => grant.entity_type && Codec.encode_enum_value(grant.entity_type),
        "role" => Codec.encode_enum_value(grant.role),
        "user_id" => grant.user_id
      }

      %{op: op, type: RoleGrant, entity_id: grant.id, data: data}
    end

    defp stored_grant(user_id) do
      RoleGrant
      |> Query.filter(user_id: ^user_id)
      |> Stage.normalize()
      |> QueryRunner.run(DB.mapping())
      |> hd()
    end

    test "answers the stored grants when no effect touched them" do
      user = create_user("user_90@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      assert [grant] = grants_before(user.id, [])
      assert grant.id == stored_grant(user.id).id
    end

    test "leaves out a grant created since" do
      user = create_user("user_91@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)
      grant = held_grant(user.id)

      assert grants_before(user.id, [grant_effect(:put_entity, grant)]) == []
    end

    test "puts back a grant revoked since" do
      user = create_user("user_92@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)
      revoked = stored_grant(user.id)
      revoke_role(user, :editor, resource)

      assert [grant] = grants_before(user.id, [grant_effect(:del_entity, revoked)])
      assert grant.id == revoked.id
      assert grant.entity_id == resource.id
      assert grant.entity_type == Module1
      assert grant.role == :editor
      assert grant.user_id == user.id
    end

    # Forwards, the creation would be undone before the deletion put it back - leaving a grant
    # the user never held at the place being asked about.
    test "answers nothing for a grant given and taken back since" do
      user = create_user("user_93@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)
      grant = held_grant(user.id)
      revoke_role(user, :editor, resource)

      effects = [grant_effect(:put_entity, grant), grant_effect(:del_entity, grant)]

      assert grants_before(user.id, effects) == []
    end

    test "answers the grant a revoke and re-grant replaced" do
      user = create_user("user_94@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)
      revoked = stored_grant(user.id)
      revoke_role(user, :editor, resource)
      grant_role(user, :owner, resource)
      current = stored_grant(user.id)

      effects = [grant_effect(:del_entity, revoked), grant_effect(:put_entity, current)]

      assert [grant] = grants_before(user.id, effects)
      assert grant.id == revoked.id
      assert grant.role == :editor
    end
  end

  describe "grant_role/2" do
    test "mints the row's id from the grant" do
      user = create_user("user_117@example.com")

      grant_role(user, Role.Module1)

      assert grant_id(user.id) == RoleGrant.derive_id(user.id, nil, nil, Role.Module1)
    end

    test "writes a global grant with no resource" do
      user = create_user("user_4@example.com")

      assert grant_role(user, Role.Module1) == :ok

      assert [
               %{
                 entity_type: nil,
                 entity_id: nil,
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
    # The store has one identity scheme whoever writes it - a grant made here and the same grant
    # made from a browser are one row, and this is the half a command makes.
    test "mints the row's id from the grant" do
      user = create_user("user_116@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      entity_type = Module1

      assert grant_id(user.id) ==
               RoleGrant.derive_id(user.id, entity_type, resource.id, :editor)
    end

    test "writes an instance grant naming the resource type and id" do
      user = create_user("user_7@example.com")

      resource = create_resource()

      assert grant_role(user, :owner, resource) == :ok

      assert [%{entity_type: "Hologram.Test.Fixtures.Policy.Module1", role: "owner"} = grant] =
               grant_rows(user.id)

      assert grant.entity_id == resource.id
    end

    test "writes a type-wide grant with no entity id" do
      user = create_user("user_8@example.com")

      assert grant_role(user, :owner, Module1) == :ok

      assert [
               %{
                 entity_type: "Hologram.Test.Fixtures.Policy.Module1",
                 entity_id: nil,
                 role: "owner"
               }
             ] = grant_rows(user.id)
    end

    test "stamps the acting user as the granter" do
      granter = create_user("user_9@example.com")
      user = create_user("user_10@example.com")

      resource = create_resource()

      grant_role(granter, :owner, resource)

      Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end)

      assert [%{granted_by_id: granted_by_id}] = grant_rows(user.id)
      assert granted_by_id == granter.id
    end

    test "leaves the granter unset outside an actor context" do
      user = create_user("user_11@example.com")

      grant_role(user, :owner, Module1)

      assert [%{granted_by_id: nil}] = grant_rows(user.id)
    end

    test "keeps the original grant when the role is already held" do
      granter = create_user("user_12@example.com")
      user = create_user("user_13@example.com")

      resource = create_resource()

      grant_role(granter, :owner, resource)

      Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end)
      [original_grant] = grant_rows(user.id)

      assert grant_role(user, :editor, resource) == :ok

      assert grant_rows(user.id) == [original_grant]
    end

    test "grants a role the acting user's role extends" do
      granter = create_user("user_16@example.com")
      user = create_user("user_17@example.com")

      resource = create_resource()

      grant_role(granter, :owner, resource)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end) == :ok

      assert [%{role: "editor"}] = grant_rows(user.id)
    end

    test "grants the acting user's own role" do
      granter = create_user("user_65@example.com")
      user = create_user("user_66@example.com")

      resource = create_parent()

      grant_role(granter, :member, resource)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :member, resource) end) == :ok

      assert [%{role: "member"}] = grant_rows(user.id)
    end

    test "grants under a global role the line names" do
      granter = create_user("user_77@example.com")
      user = create_user("user_78@example.com")

      resource = create_parent()

      grant_role(granter, Role.Module1)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :admin, resource) end) == :ok

      assert [%{role: "admin"}] = grant_rows(user.id)
    end

    test "grants under a global role extending the one the line names" do
      granter = create_user("user_79@example.com")
      user = create_user("user_80@example.com")

      resource = create_parent()

      grant_role(granter, Role.Module2)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :member, resource) end) ==
               :ok

      assert [%{role: "member"}] = grant_rows(user.id)
    end

    test "grants under a type-wide role" do
      granter = create_user("user_81@example.com")
      user = create_user("user_82@example.com")

      resource = create_resource()

      grant_role(granter, :owner, Module1)

      assert Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end) == :ok

      assert [%{role: "editor"}] = grant_rows(user.id)
    end

    test "raises when the acting user holds no role on the resource" do
      granter = create_user("user_18@example.com")
      user = create_user("user_19@example.com")

      resource = create_resource()

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)} that may grant :editor"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, :editor, resource) end)
      end
    end

    test "raises when the role is above the acting user's own" do
      granter = create_user("user_67@example.com")
      user = create_user("user_68@example.com")

      resource = create_resource()

      grant_role(granter, :editor, resource)

      expected_msg =
        "the acting user holds :editor on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}, " <>
          "which may grant no role there, :owner included. :owner extends :editor, so it holds more. " <>
          "Declare `allow {:grant_role, :owner}, to: :editor` on Hologram.Test.Fixtures.Policy.Module1 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, :owner, resource) end)
      end
    end

    test "raises naming what the acting user's role may grant instead" do
      granter = create_user("user_69@example.com")
      user = create_user("user_70@example.com")

      resource = create_parent()

      grant_role(granter, :member, resource)

      expected_msg =
        "the acting user holds :member on Hologram.Test.Fixtures.Policy.Module2 #{inspect(resource.id)}, " <>
          "which may grant :member but not :admin. " <>
          "Declare `allow {:grant_role, :admin}, to: :member` on Hologram.Test.Fixtures.Policy.Module2 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, :admin, resource) end)
      end
    end

    test "raises on a type-wide grant issued by an acting user" do
      granter = create_user("user_20@example.com")
      user = create_user("user_21@example.com")

      expected_msg =
        "type-wide roles are granted only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> grant_role(user, :owner, Module1) end)
      end
    end

    test "raises on a role the resource type does not declare" do
      user = create_user("user_14@example.com")

      expected_msg =
        "unknown role :publisher for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error ArgumentError, expected_msg, fn -> grant_role(user, :publisher, Module1) end
    end

    test "raises on an entity id that is not a canonical entity id" do
      user = create_user("user_15@example.com")

      expected_msg =
        "invalid entity id \"nope\" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings"

      assert_error ArgumentError, expected_msg, fn ->
        grant_role(user, :owner, %Module1{id: "nope"})
      end
    end
  end

  describe "apply_grant_write/3" do
    test "answers :created and writes the grant under a holder who may grant the role" do
      granter = create_user("user_95@example.com")
      user = create_user("user_96@example.com")
      resource = create_resource()

      grant_role(granter, :owner, resource)

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: granter.id,
          entity_id: resource.id,
          role: :editor,
          user_id: user.id
        )

      assert apply_grant_write(grant, granter.id, MapSet.new()) == :created

      assert [row] = grant_rows(user.id)
      assert row.granted_by_id == granter.id
      assert row.entity_id == resource.id
      assert row.role == "editor"
    end

    test "answers :present for a grant the store already holds" do
      granter = create_user("user_97@example.com")
      user = create_user("user_98@example.com")
      resource = create_resource()

      grant_role(granter, :owner, resource)
      grant_role(user, :editor, resource)

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: granter.id,
          entity_id: resource.id,
          role: :editor,
          user_id: user.id
        )

      assert apply_grant_write(grant, granter.id, MapSet.new()) == :present

      assert [%{role: "editor"}] = grant_rows(user.id)
    end

    # granted_to: :creator is a declaration rather than a permission somebody holds, so the grant
    # a browser sends beside its create passes no gate - which is what lets a type declare a
    # creator role without also declaring who may grant it. Module1 lets only an owner grant, and
    # this actor holds nothing there.
    test "writes a creator's grant on a row the batch created, asking no gate" do
      creator = create_user("user_119@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: creator.id,
          entity_id: resource.id,
          role: :maintainer,
          user_id: creator.id
        )

      created = MapSet.new([{Module1, resource.id}])

      assert apply_grant_write(grant, creator.id, created) == :created

      assert [%{role: "maintainer"}] = grant_rows(creator.id)
    end

    # A client is never the trusted tier, so the sentence the verb keeps for an acting user is
    # unconditional here - there is no batch without a session to run it.
    test "refuses a type-wide grant" do
      granter = create_user("user_99@example.com")
      user = create_user("user_100@example.com")

      grant = grant_struct(entity_type: Module1, role: :owner, user_id: user.id)

      expected_msg =
        "type-wide roles are granted only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, granter.id, MapSet.new())
      end
    end

    test "refuses a global grant" do
      granter = create_user("user_101@example.com")
      user = create_user("user_102@example.com")

      grant = grant_struct(role: Role.Module1, user_id: user.id)

      expected_msg =
        "global roles are granted only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, granter.id, MapSet.new())
      end
    end

    # Where the verb reads an absent actor as trusted code running a script, a batch has a session
    # behind it either way - so an absent one is an anonymous visitor, who grants nothing.
    test "refuses a grant with nobody signed in" do
      user = create_user("user_103@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          entity_id: resource.id,
          role: :editor,
          user_id: user.id
        )

      expected_msg = "a role is granted only by a signed-in user - nobody is signed in"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, nil, MapSet.new())
      end
    end

    # The verb raises an ArgumentError for this; a batch cannot be answered with a raise, so the
    # same violation comes back the way a create naming no row does.
    test "answers the grantee as not found for a user that does not exist" do
      granter = create_user("user_118@example.com")
      resource = create_resource()

      grant_role(granter, :owner, resource)

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: granter.id,
          entity_id: resource.id,
          role: :editor,
          user_id: Entity.generate_id()
        )

      assert apply_grant_write(grant, granter.id, MapSet.new()) ==
               {:error, %{user_id: [:not_found]}}
    end

    test "refuses a role the acting user's own roles do not cover" do
      granter = create_user("user_104@example.com")
      user = create_user("user_105@example.com")
      resource = create_parent()

      grant_role(granter, :member, resource)

      grant =
        grant_struct(
          entity_type: Module2,
          granted_by_id: granter.id,
          entity_id: resource.id,
          role: :admin,
          user_id: user.id
        )

      expected_msg =
        "the acting user holds :member on Hologram.Test.Fixtures.Policy.Module2 #{inspect(resource.id)}, " <>
          "which may grant :member but not :admin. " <>
          "Declare `allow {:grant_role, :admin}, to: :member` on Hologram.Test.Fixtures.Policy.Module2 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, granter.id, MapSet.new())
      end
    end

    # The three parts of a creator's grant, refused one at a time. Each falls back to the gate,
    # which is what an ordinary grant meets - so a browser can send any of these and gets the
    # answer its rules give.
    test "refuses a creator role on a row the batch did not create" do
      creator = create_user("user_120@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: creator.id,
          entity_id: resource.id,
          role: :maintainer,
          user_id: creator.id
        )

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 " <>
          "#{inspect(resource.id)} that may grant :maintainer"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, creator.id, MapSet.new())
      end
    end

    test "refuses a creator role granted to anybody but the acting user" do
      creator = create_user("user_121@example.com")
      user = create_user("user_122@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: creator.id,
          entity_id: resource.id,
          role: :maintainer,
          user_id: user.id
        )

      created = MapSet.new([{Module1, resource.id}])

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 " <>
          "#{inspect(resource.id)} that may grant :maintainer"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, creator.id, created)
      end
    end

    test "refuses a role the type does not hand its creator" do
      creator = create_user("user_123@example.com")
      resource = create_resource()

      grant =
        grant_struct(
          entity_type: Module1,
          granted_by_id: creator.id,
          entity_id: resource.id,
          role: :editor,
          user_id: creator.id
        )

      created = MapSet.new([{Module1, resource.id}])

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 " <>
          "#{inspect(resource.id)} that may grant :editor"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_grant_write(grant, creator.id, created)
      end
    end
  end

  describe "has_role?/2" do
    test "holds a global role" do
      user = create_user("user_124@example.com")

      insert_global_grant(user.id, Role.Module1)

      assert has_role?(user.id, Role.Module1)
    end

    test "holds the global role an extending module reaches" do
      user = create_user("user_125@example.com")

      insert_global_grant(user.id, Role.Module2)

      assert has_role?(user.id, Role.Module1)
    end

    test "does not hold a global role that extends the held one" do
      user = create_user("user_126@example.com")

      insert_global_grant(user.id, Role.Module1)

      refute has_role?(user.id, Role.Module2)
    end

    test "does not hold a global role granted to another user" do
      user = create_user("user_127@example.com")
      other_user = create_user("user_128@example.com")

      insert_global_grant(other_user.id, Role.Module1)

      refute has_role?(user.id, Role.Module1)
    end

    test "does not hold a global role from a role held on an entity type" do
      user = create_user("user_129@example.com")

      grant_role(user, :admin, Module2)

      refute has_role?(user.id, Role.Module1)
    end

    test "takes the user entity" do
      user = create_user("user_130@example.com")

      insert_global_grant(user.id, Role.Module1)

      assert has_role?(user, Role.Module1)
    end

    test "answers false for an anonymous session" do
      refute has_role?(nil, Role.Module1)
    end

    test "answers false for an id the framework never generated" do
      refute has_role?("not-an-id", Role.Module1)
    end

    # A check inside a render is recorded, so the rows answering it travel with the page.
    test "records the question for the render that asked it" do
      user = create_user("user_131@example.com")

      Carry.start()
      refute has_role?(user.id, Role.Module1)

      assert Carry.take_grant_scopes() == MapSet.new([{user.id, :global}])
    end

    test "raises on a module that is not a global role" do
      user = create_user("user_132@example.com")

      expected_msg =
        "unknown global role Hologram.Test.Fixtures.Entity.Module1 - defined global roles are: Hologram.Test.Fixtures.Role.Module1, Hologram.Test.Fixtures.Role.Module2"

      assert_error ArgumentError, expected_msg, fn ->
        has_role?(user, Hologram.Test.Fixtures.Entity.Module1)
      end
    end

    # The role is checked before the user, so a mistyped one fails for every session alike.
    test "raises on a module that is not a global role for an anonymous session" do
      expected_msg =
        "unknown global role Hologram.Test.Fixtures.Entity.Module1 - defined global roles are: Hologram.Test.Fixtures.Role.Module1, Hologram.Test.Fixtures.Role.Module2"

      assert_error ArgumentError, expected_msg, fn ->
        has_role?(nil, Hologram.Test.Fixtures.Entity.Module1)
      end
    end
  end

  describe "has_role?/3" do
    test "holds a role granted on the row" do
      user = create_user("user_133@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      assert has_role?(user.id, :editor, resource)
    end

    test "holds a role granted on the whole entity type" do
      user = create_user("user_134@example.com")
      resource = create_resource()

      grant_role(user, :editor, Module1)

      assert has_role?(user.id, :editor, resource)
    end

    test "holds the role an extending role reaches" do
      user = create_user("user_135@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      assert has_role?(user.id, :editor, resource)
    end

    test "does not hold a role that extends the held one" do
      user = create_user("user_136@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      refute has_role?(user.id, :owner, resource)
    end

    test "does not hold a role granted on another row" do
      user = create_user("user_137@example.com")
      resource_1 = create_resource()
      resource_2 = create_resource()

      grant_role(user, :editor, resource_1)

      refute has_role?(user.id, :editor, resource_2)
    end

    test "does not hold a role granted to another user" do
      user = create_user("user_138@example.com")
      other_user = create_user("user_139@example.com")
      resource = create_resource()

      grant_role(other_user, :editor, resource)

      refute has_role?(user.id, :editor, resource)
    end

    test "takes the user entity" do
      user = create_user("user_140@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      assert has_role?(user, :editor, resource)
    end

    test "answers false for an anonymous session" do
      resource = create_resource()

      refute has_role?(nil, :editor, resource)
    end

    test "answers false for an id the framework never generated" do
      resource = create_resource()

      refute has_role?("not-an-id", :editor, resource)
    end

    test "matches the type-wide grant alone on a struct with no id" do
      user = create_user("user_141@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      refute has_role?(user.id, :editor, %Module1{})

      grant_role(user, :viewer, Module1)

      assert has_role?(user.id, :viewer, %Module1{})
    end

    test "asks about the type-wide grant alone when given the entity type" do
      user = create_user("user_142@example.com")
      resource = create_resource()

      grant_role(user, :editor, resource)

      refute has_role?(user.id, :editor, Module1)

      grant_role(user, :editor, Module1)

      assert has_role?(user.id, :editor, Module1)
    end

    # A check inside a render is recorded, so the rows answering it travel with the page.
    test "records the question for the render that asked it" do
      user = create_user("user_143@example.com")
      resource = create_resource()

      Carry.start()
      refute has_role?(user.id, :editor, resource)
      refute has_role?(user.id, :editor, Module1)

      assert Carry.take_grant_scopes() ==
               MapSet.new([
                 {user.id, {:own, Module1, resource.id}},
                 {user.id, {:type, Module1}}
               ])
    end

    test "raises on a role the entity type does not declare" do
      user = create_user("user_144@example.com")
      resource = create_resource()

      expected_msg =
        "unknown role :publisher for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error ArgumentError, expected_msg, fn ->
        has_role?(user, :publisher, resource)
      end
    end

    test "raises on a role for an entity type declaring none" do
      user = create_user("user_145@example.com")

      expected_msg =
        "unknown role :editor for Hologram.Test.Fixtures.Entity.Module4 - declared roles are: "

      assert_error ArgumentError, expected_msg, fn ->
        has_role?(user, :editor, %Hologram.Test.Fixtures.Entity.Module4{})
      end
    end

    # The role is checked before the user, so a mistyped one fails for every session alike.
    test "raises on a role the entity type does not declare for an anonymous session" do
      resource = create_resource()

      expected_msg =
        "unknown role :publisher for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error ArgumentError, expected_msg, fn ->
        has_role?(nil, :publisher, resource)
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

      grant_role(user, :owner, resource)

      assert revoke_role(user, :owner, resource) == :ok
      assert grant_rows(user.id) == []
    end

    test "records the removal of an instance grant" do
      user = create_user("user_52@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)
      revoked_id = grant_id(user.id)

      revoke_role(user, :owner, resource)

      assert revocation_effects() == [{"Hologram.Auth.RoleGrant", revoked_id}]
    end

    test "lets a user revoke their own role" do
      owner = create_user("user_29@example.com")
      member = create_user("user_30@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(member, :editor, resource)

      assert Context.with_actor(member.id, fn -> revoke_role(member, :editor, resource) end) ==
               :ok

      assert grant_rows(member.id) == []
    end

    test "removes another user's role the acting user's role extends" do
      owner = create_user("user_31@example.com")
      member = create_user("user_32@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(member, :editor, resource)

      assert Context.with_actor(owner.id, fn -> revoke_role(member, :editor, resource) end) == :ok

      assert grant_rows(member.id) == []
    end

    test "removes another user's role equal to the acting user's own" do
      member = create_user("user_71@example.com")
      other_member = create_user("user_72@example.com")
      resource = create_parent()

      grant_role(member, :member, resource)
      grant_role(other_member, :member, resource)

      assert Context.with_actor(member.id, fn ->
               revoke_role(other_member, :member, resource)
             end) == :ok

      assert grant_rows(other_member.id) == []
    end

    test "removes another user's role under a global role the line names" do
      admin = create_user("user_83@example.com")
      member = create_user("user_84@example.com")
      global_holder = create_user("user_85@example.com")
      resource = create_parent()

      grant_role(admin, :admin, resource)
      grant_role(member, :member, resource)
      grant_role(global_holder, Role.Module1)

      assert Context.with_actor(global_holder.id, fn ->
               revoke_role(member, :member, resource)
             end) == :ok

      assert grant_rows(member.id) == []
    end

    test "raises when the acting user holds no role on the resource" do
      member = create_user("user_73@example.com")
      other_user = create_user("user_74@example.com")
      resource = create_resource()

      grant_role(member, :editor, resource)

      expected_msg =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)} that may revoke :editor"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(other_user.id, fn -> revoke_role(member, :editor, resource) end)
      end
    end

    test "raises when the acting user's role may not revoke it" do
      member = create_user("user_33@example.com")
      other_member = create_user("user_34@example.com")
      resource = create_resource()

      grant_role(member, :editor, resource)
      grant_role(other_member, :editor, resource)

      expected_msg =
        "the acting user holds :editor on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}, " <>
          "which may revoke no role there, :editor included. " <>
          "Declare `allow {:revoke_role, :editor}, to: :editor` on Hologram.Test.Fixtures.Policy.Module1 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(other_member.id, fn -> revoke_role(member, :editor, resource) end)
      end
    end

    test "raises when the role is above the acting user's own" do
      owner = create_user("user_75@example.com")
      editor = create_user("user_76@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      expected_msg =
        "the acting user holds :editor on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}, " <>
          "which may revoke no role there, :owner included. :owner extends :editor, so it holds more. " <>
          "Declare `allow {:revoke_role, :owner}, to: :editor` on Hologram.Test.Fixtures.Policy.Module1 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(editor.id, fn -> revoke_role(owner, :owner, resource) end)
      end
    end

    test "raises on a type-wide revocation issued by an acting user" do
      granter = create_user("user_39@example.com")
      user = create_user("user_40@example.com")

      expected_msg =
        "type-wide roles are revoked only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        Context.with_actor(granter.id, fn -> revoke_role(user, :owner, Module1) end)
      end
    end
  end

  describe "apply_revocation_write/2" do
    # An editor may not revoke on Module1 - the rule names :owner - so this passes only because the
    # row is the actor's own, which is how a member leaves a resource.
    test "revokes the acting user's own row without asking the gate" do
      owner = create_user("user_106@example.com")
      editor = create_user("user_107@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      grant = held_grant(editor.id)

      assert apply_revocation_write(grant, editor.id) == :ok
      assert grant_rows(editor.id) == []
    end

    test "revokes another user's row under a role that may" do
      owner = create_user("user_108@example.com")
      editor = create_user("user_109@example.com")
      resource = create_resource()

      grant_role(owner, :owner, resource)
      grant_role(editor, :editor, resource)

      grant = held_grant(editor.id)

      assert apply_revocation_write(grant, owner.id) == :ok
      assert grant_rows(editor.id) == []
    end

    test "refuses another user's row under a role that may not" do
      first_editor = create_user("user_110@example.com")
      second_editor = create_user("user_111@example.com")
      resource = create_resource()

      grant_role(first_editor, :editor, resource)
      grant_role(second_editor, :editor, resource)

      grant = held_grant(second_editor.id)

      expected_msg =
        "the acting user holds :editor on Hologram.Test.Fixtures.Policy.Module1 #{inspect(resource.id)}, " <>
          "which may revoke no role there, :editor included. " <>
          "Declare `allow {:revoke_role, :editor}, to: :editor` on Hologram.Test.Fixtures.Policy.Module1 if that is intended."

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_revocation_write(grant, first_editor.id)
      end
    end

    test "refuses a type-wide revocation" do
      actor = create_user("user_113@example.com")
      user = create_user("user_114@example.com")

      grant_role(user, :owner, Module1)

      grant = held_grant(user.id)

      expected_msg =
        "type-wide roles are revoked only by trusted code running without an acting user"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_revocation_write(grant, actor.id)
      end
    end

    test "refuses a revocation with nobody signed in" do
      user = create_user("user_115@example.com")
      resource = create_resource()

      grant_role(user, :owner, resource)

      grant = held_grant(user.id)

      expected_msg = "a role is revoked only by a signed-in user - nobody is signed in"

      assert_error Hologram.AccessDeniedError, expected_msg, fn ->
        apply_revocation_write(grant, nil)
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
