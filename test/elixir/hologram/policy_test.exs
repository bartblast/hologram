defmodule Hologram.PolicyTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy,
    only: [
      build: 1,
      dead_entity_types: 1,
      grant_role_qualifying_roles: 1,
      grant_role_qualifying_roles: 2,
      operation_key: 1,
      read_roles_qualifying_roles: 1,
      revoke_role_qualifying_roles: 1,
      revoke_role_qualifying_roles: 2
    ]

  alias Hologram.Auth.RoleGrant
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Policy
  alias Hologram.Test.Fixtures.Role

  describe "__declaration_sources__/0" do
    test "returns empty list for a policy module with no declarations" do
      defmodule EmptySourcesPolicyFixture do
        use Hologram.Policy
      end

      assert EmptySourcesPolicyFixture.__declaration_sources__() == []
    end

    test "names the policy module itself for its own declarations" do
      defmodule OwnSourcesPolicyFixture do
        use Hologram.Policy

        role :viewer

        allow :read, to: :viewer
      end

      assert OwnSourcesPolicyFixture.__declaration_sources__() == [
               OwnSourcesPolicyFixture,
               OwnSourcesPolicyFixture
             ]
    end

    test "keeps the module a taken declaration was written in" do
      defmodule TakenSourcesPolicyFixture do
        use Hologram.Policy

        role :viewer

        allow :read, to: :viewer
      end

      defmodule TakingSourcesPolicyFixture do
        use Hologram.Policy

        policy TakenSourcesPolicyFixture

        allow :update, to: :viewer
      end

      assert TakingSourcesPolicyFixture.__declaration_sources__() == [
               TakenSourcesPolicyFixture,
               TakenSourcesPolicyFixture,
               TakingSourcesPolicyFixture
             ]
    end
  end

  describe "__declarations__/0" do
    test "returns empty list for a policy module with no declarations" do
      defmodule EmptyDeclarationsPolicyFixture do
        use Hologram.Policy
      end

      assert EmptyDeclarationsPolicyFixture.__declarations__() == []
    end

    test "returns the role and allow declarations in declaration order" do
      defmodule DeclarationsPolicyFixture do
        use Hologram.Policy

        role :viewer

        allow :read, to: :viewer
      end

      assert DeclarationsPolicyFixture.__declarations__() == [
               {:role, :viewer, []},
               {:allow, :read, [to: :viewer]}
             ]
    end
  end

  describe "__is_hologram_policy__/0" do
    test "returns true" do
      defmodule IsPolicyFixture do
        use Hologram.Policy
      end

      assert IsPolicyFixture.__is_hologram_policy__()
    end
  end

  describe "allow/2" do
    test "replays declarations into the including entity type in declaration order" do
      defmodule AllowPolicyFixture do
        use Hologram.Policy

        allow :read
        allow :update, to: :editor
      end

      defmodule AllowEntityFixture do
        use Hologram.Entity

        policy AllowPolicyFixture

        role :editor

        allow :publish
      end

      assert AllowEntityFixture.__policies__() == [
               {:read, nil, nil, []},
               {:update, :editor, nil, []},
               {:publish, nil, nil, []}
             ]
    end

    test "replaces a user_id() call with the actor sentinel" do
      defmodule ActorPolicyFixture do
        use Hologram.Policy

        allow :archive, id: user_id()
      end

      defmodule ActorEntityFixture do
        use Hologram.Entity

        policy ActorPolicyFixture
      end

      assert build(ActorEntityFixture)[:archive] == [
               %{predicates: [{:id, :==, {:actor}}], to: nil, via: nil}
             ]
    end

    test "replays a global role module reference intact" do
      defmodule GlobalReferencePolicyFixture do
        use Hologram.Policy

        alias Hologram.Test.Fixtures.Role.Module1

        allow :read, to: Module1
      end

      defmodule GlobalReferenceEntityFixture do
        use Hologram.Entity

        policy GlobalReferencePolicyFixture
      end

      assert build(GlobalReferenceEntityFixture)[:read] == [
               %{predicates: [], to: [{:global, [Role.Module1, Role.Module2]}], via: nil}
             ]
    end

    test "keeps the same line declared by two policies" do
      defmodule DuplicateLinePolicyFixture1 do
        use Hologram.Policy

        allow :read
      end

      defmodule DuplicateLinePolicyFixture2 do
        use Hologram.Policy

        allow :read
      end

      defmodule DuplicateLineEntityFixture do
        use Hologram.Entity

        policy DuplicateLinePolicyFixture1
        policy DuplicateLinePolicyFixture2
      end

      assert DuplicateLineEntityFixture.__policies__() == [
               {:read, nil, nil, []},
               {:read, nil, nil, []}
             ]
    end

    test "raises at the policy module's own compile for an invalid declaration" do
      expected_msg =
        "invalid operation 123 used for allow in Hologram.PolicyTest.InvalidAllowPolicyFixture - a policy operation is an atom, or {:grant_role, role} / {:revoke_role, role} naming a declared role or a list of them"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InvalidAllowPolicyFixture do
          use Hologram.Policy

          allow 123
        end
      end
    end
  end

  describe "policy/1" do
    test "takes the declarations of another policy, in order" do
      defmodule TakenPolicyFixture do
        use Hologram.Policy

        role :viewer

        allow :read, to: :viewer
      end

      defmodule TakingPolicyFixture do
        use Hologram.Policy

        policy TakenPolicyFixture

        allow :update, to: :viewer
      end

      assert TakingPolicyFixture.__declarations__() == [
               {:role, :viewer, []},
               {:allow, :read, [to: :viewer]},
               {:allow, :update, [to: :viewer]}
             ]
    end

    test "carries the declarations of a policy nested two levels down into an entity type" do
      defmodule MiddlePolicyFixture do
        use Hologram.Policy

        policy Policy.Shared.Module1

        allow :update, to: :viewer
      end

      defmodule OuterPolicyFixture do
        use Hologram.Policy

        policy MiddlePolicyFixture

        allow :delete, to: :viewer
      end

      defmodule NestedEntityFixture do
        use Hologram.Entity

        policy OuterPolicyFixture
      end

      assert NestedEntityFixture.__roles__() == [{:viewer, []}]

      assert NestedEntityFixture.__policies__() == [
               {:read, :viewer, nil, []},
               {:update, :viewer, nil, []},
               {:delete, :viewer, nil, []}
             ]

      # A line taken through two hops names the module whose body wrote it, not the last hop.
      assert NestedEntityFixture.__policy_sources__() == [
               Policy.Shared.Module1,
               MiddlePolicyFixture,
               OuterPolicyFixture
             ]
    end

    test "raises for a target that is not a policy module" do
      expected_msg =
        "invalid policy Hologram.Test.Fixtures.Entity.Module1 taken in Hologram.PolicyTest.NonPolicyTargetPolicyFixture - Hologram.Test.Fixtures.Entity.Module1 is not a policy module (define it with use Hologram.Policy)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule NonPolicyTargetPolicyFixture do
          use Hologram.Policy

          policy Module1
        end
      end
    end
  end

  describe "role/2" do
    test "replays a role declaration into the including entity type" do
      defmodule RolePolicyFixture do
        use Hologram.Policy

        role :moderator, granted_to: :creator
      end

      defmodule RoleEntityFixture do
        use Hologram.Entity

        policy RolePolicyFixture

        role :owner
      end

      assert RoleEntityFixture.__roles__() == [{:moderator, [granted_to: :creator]}, {:owner, []}]
    end

    test "unifies the same role declared by two policies" do
      defmodule DuplicateRolePolicyFixture1 do
        use Hologram.Policy

        role :moderator
      end

      defmodule DuplicateRolePolicyFixture2 do
        use Hologram.Policy

        role :moderator
      end

      defmodule DuplicateRoleEntityFixture do
        use Hologram.Entity

        policy DuplicateRolePolicyFixture1
        policy DuplicateRolePolicyFixture2
      end

      assert DuplicateRoleEntityFixture.__roles__() == [{:moderator, []}]
    end

    test "raises at the policy module's own compile for an invalid declaration" do
      expected_msg =
        "invalid name \"moderator\" used for role in Hologram.PolicyTest.InvalidRolePolicyFixture - declaration names must be atoms"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InvalidRolePolicyFixture do
          use Hologram.Policy

          role "moderator"
        end
      end
    end
  end

  describe "build/1" do
    test "returns empty map for entity type without policy declarations" do
      assert build(Module1) == %{}
    end

    test "builds rules per operation, keeping declaration order" do
      owner_rule = %{predicates: [], to: [{:own, [:owner]}], via: nil}

      assert build(Policy.Module1) == %{
               :archive => [
                 %{predicates: [{:author_id, :==, {:actor}}], to: nil, via: nil}
               ],
               :delete => [
                 %{predicates: [], to: [{:rel, :parent, [:admin]}], via: nil}
               ],
               :grant_role => [owner_rule, owner_rule],
               :publish => [
                 %{predicates: [], to: nil, via: :parent}
               ],
               :read => [
                 %{predicates: [{:public, :==, true}], to: nil, via: nil},
                 %{
                   predicates: [],
                   to: [{:own, [:viewer]}, {:type, Policy.Module2, [:admin]}],
                   via: nil
                 }
               ],
               :revoke_role => [owner_rule, owner_rule],
               :update => [
                 %{predicates: [{:priority, :>=, 3}], to: [{:own, [:editor, :owner]}], via: nil}
               ],
               {:grant_role, :editor} => [owner_rule],
               {:grant_role, :owner} => [owner_rule],
               {:revoke_role, :editor} => [owner_rule],
               {:revoke_role, :owner} => [owner_rule]
             }
    end
  end

  describe "build/1 for the grant lifecycle operations" do
    test "derives which roles a bare line covers from what its holders hold and extend" do
      defmodule BareGrantLineFixture do
        use Hologram.Entity

        role :editor
        role :owner, extends: :editor
        role :viewer

        allow :grant_role, to: :editor
      end

      assert build(BareGrantLineFixture) == %{
               :grant_role => [
                 %{predicates: [], to: [{:own, [:editor, :owner]}], via: nil},
                 %{predicates: [], to: [{:own, [:owner]}], via: nil}
               ],
               {:grant_role, :editor} => [
                 %{predicates: [], to: [{:own, [:editor, :owner]}], via: nil}
               ],
               {:grant_role, :owner} => [
                 %{predicates: [], to: [{:own, [:owner]}], via: nil}
               ]
             }
    end

    test "expands a line naming several roles into one key per role" do
      defmodule RoleListLineFixture do
        use Hologram.Entity

        role :editor
        role :viewer

        allow {:revoke_role, [:viewer, :editor]}, to: :editor
      end

      editor_rule = %{predicates: [], to: [{:own, [:editor]}], via: nil}

      assert build(RoleListLineFixture) == %{
               :revoke_role => [editor_rule, editor_rule],
               {:revoke_role, :editor} => [editor_rule],
               {:revoke_role, :viewer} => [editor_rule]
             }
    end

    test "keeps a line naming one role as written, under the bare key as well" do
      defmodule SingleRoleLineFixture do
        use Hologram.Entity

        role :editor
        role :viewer

        allow {:grant_role, :viewer}, to: :editor
      end

      viewer_rule = %{predicates: [], to: [{:own, [:editor]}], via: nil}

      assert build(SingleRoleLineFixture) == %{
               :grant_role => [viewer_rule],
               {:grant_role, :viewer} => [viewer_rule]
             }
    end
  end

  describe "build/1 with global role references" do
    test "expands a role module reference to every role carrying it" do
      defmodule GlobalReferenceFixture do
        use Hologram.Entity

        allow :archive, to: Hologram.Test.Fixtures.Role.Module1
      end

      assert build(GlobalReferenceFixture)[:archive] == [
               %{
                 predicates: [],
                 to: [{:global, [Role.Module1, Role.Module2]}],
                 via: nil
               }
             ]
    end

    test "keeps own and global references of one line apart" do
      defmodule MixedReferenceFixture do
        use Hologram.Entity

        role :viewer

        allow :read, to: [:viewer, Hologram.Test.Fixtures.Role.Module2]
      end

      assert build(MixedReferenceFixture)[:read] == [
               %{
                 predicates: [],
                 to: [{:own, [:viewer]}, {:global, [Role.Module2]}],
                 via: nil
               }
             ]
    end
  end

  describe "build/1 for the grant store" do
    test "grants sight of own grants, and of others' grants to read-grants role holders" do
      assert build(RoleGrant) == %{
               read: [
                 %{predicates: [{:user_id, :==, {:actor}}], to: nil, via: nil},
                 %{
                   predicates: [{:resource_type, :==, :test_fixtures_policy_module1}],
                   to: [{:resource, Policy.Module1, [:owner]}],
                   via: nil
                 },
                 %{
                   predicates: [{:resource_type, :==, :test_fixtures_policy_module2}],
                   to: [{:resource, Policy.Module2, [:admin, :member]}],
                   via: nil
                 }
               ]
             }
    end
  end

  describe "dead_entity_types/1" do
    test "returns the entity types declaring no allow lines, sorted" do
      assert dead_entity_types([Policy.Module1, Module14, Module2, Module1, Module4]) == [
               Module1,
               Module4
             ]
    end

    test "returns empty list when every entity type declares an allow line" do
      assert dead_entity_types([Policy.Module1, Policy.Module2]) == []
    end

    test "never returns the grant store" do
      assert dead_entity_types([RoleGrant]) == []
    end
  end

  describe "grant_role_qualifying_roles/1" do
    test "returns the expanded own roles across the grant_role rules" do
      assert grant_role_qualifying_roles(Policy.Module1) == [:owner]
    end

    test "returns empty list when the entity type declares no grant_role rule" do
      assert grant_role_qualifying_roles(Policy.Module3) == []
    end
  end

  describe "grant_role_qualifying_roles/2" do
    test "returns the expanded own roles of the rules covering the given role" do
      assert grant_role_qualifying_roles(Policy.Module1, :editor) == [:owner]
    end

    test "returns empty list when no rule covers the given role" do
      assert grant_role_qualifying_roles(Policy.Module1, :viewer) == []
    end
  end

  describe "operation_key/1" do
    test "spells an atom operation as its name" do
      assert operation_key(:read) == "read"
    end

    test "joins a per-role operation with a colon" do
      assert operation_key({:grant_role, :viewer}) == "grant_role:viewer"
    end
  end

  describe "read_roles_qualifying_roles/1" do
    test "adds the declared readers to the roles qualifying to grant or revoke" do
      assert read_roles_qualifying_roles(Policy.Module2) == [:admin, :member]
    end

    test "defaults to the roles qualifying to grant or revoke" do
      assert read_roles_qualifying_roles(Policy.Module1) == [:owner]
    end
  end

  describe "revoke_role_qualifying_roles/1" do
    test "returns the expanded own roles across the revoke_role rules" do
      assert revoke_role_qualifying_roles(Policy.Module1) == [:owner]
    end

    test "returns empty list when the entity type declares no revoke_role rule" do
      assert revoke_role_qualifying_roles(Policy.Module3) == []
    end
  end

  describe "revoke_role_qualifying_roles/2" do
    test "returns the expanded own roles of the rules covering the given role" do
      assert revoke_role_qualifying_roles(Policy.Module1, :editor) == [:owner]
    end

    test "returns empty list when no rule covers the given role" do
      assert revoke_role_qualifying_roles(Policy.Module1, :viewer) == []
    end
  end
end
