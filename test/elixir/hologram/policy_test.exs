defmodule Hologram.PolicyTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy,
    only: [
      build: 1,
      dead_entity_types: 1,
      deciding_quantifier?: 3,
      delegation: 2,
      expand_global_role: 1,
      expand_global_role: 2,
      field_rules: 2,
      framework_operations: 0,
      grant_role_qualifying_roles: 1,
      grant_role_qualifying_roles: 2,
      hash: 1,
      held_chains: 2,
      line_held_chains: 2,
      locked_set_links: 1,
      operation_key: 1,
      operation_reads: 2,
      operation_rules: 2,
      operations: 1,
      read_roles_qualifying_role_modules: 1,
      read_roles_qualifying_roles: 1,
      readable_prefix: 2,
      readable_type?: 1,
      related_chains: 1,
      related_chains: 2,
      revoke_role_qualifying_roles: 1,
      revoke_role_qualifying_roles: 2,
      stored_spelling: 1,
      update_fields: 1,
      validate_operation!: 2,
      verdict_key: 2,
      verdict_operations: 1,
      verdict_reads: 2,
      verdict_related_reads: 2
    ]

  alias Hologram.Auth.RoleGrant
  alias Hologram.Entity.Derived
  alias Hologram.MisuseError
  alias Hologram.PolicyTest.HeldBoard
  alias Hologram.PolicyTest.HeldTask
  alias Hologram.PolicyTest.ServerOnlyReport
  alias Hologram.PolicyTest.VerdictLabel
  alias Hologram.PolicyTest.VerdictMember
  alias Hologram.PolicyTest.VerdictProject
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module42
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

        allow :update, as: :publish
      end

      assert AllowEntityFixture.__policies__() == [
               {:read, nil, nil, [], nil, nil},
               {:update, :editor, nil, [], nil, nil},
               {:update, nil, nil, [], :publish, nil}
             ]
    end

    test "replaces a user_id() call with the actor sentinel" do
      defmodule ActorPolicyFixture do
        use Hologram.Policy

        allow :update, as: :archive, when: id == user_id()
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
               {:read, nil, nil, [], nil, nil},
               {:read, nil, nil, [], nil, nil}
             ]
    end

    test "raises at the policy module's own compile for an operation that is not the framework's" do
      expected_msg =
        "unknown operation :archive used for allow in Hologram.PolicyTest.CustomOperationPolicyFixture - an allow line names one of the framework's operations, :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update. To keep :archive as a name can? and via: ask by, put it on a line of the operation the rule grants, like allow :update, as: :archive, only: [...] or allow :delete, as: :archive"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule CustomOperationPolicyFixture do
          use Hologram.Policy

          allow :archive
        end
      end
    end

    test "raises at the policy module's own compile for an invalid declaration" do
      expected_msg =
        "invalid operation 123 used for allow in Hologram.PolicyTest.InvalidAllowPolicyFixture - an allow line names a framework operation, or {:grant_role, role} / {:revoke_role, role} naming a declared role or a list of them"

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
               {:read, :viewer, nil, [], nil, nil},
               {:update, :viewer, nil, [], nil, nil},
               {:delete, :viewer, nil, [], nil, nil}
             ]

      # A line taken through two hops names the module whose body wrote it, not the last hop.
      assert NestedEntityFixture.__policy_sources__() == [
               Policy.Shared.Module1,
               MiddlePolicyFixture,
               OuterPolicyFixture
             ]
    end

    test "carries the hints of a condition through a policy taken by a policy into an entity type" do
      defmodule HintsInnerPolicyFixture do
        use Hologram.Policy

        allow :read, when: any(message <- messages, message.position > 1)
      end

      defmodule HintsOuterPolicyFixture do
        use Hologram.Policy

        policy HintsInnerPolicyFixture
      end

      defmodule HintsEntityFixture do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :messages, [Module33]

        policy HintsOuterPolicyFixture

        allow :delete, to: :viewer
      end

      assert HintsEntityFixture.__policy_hints__() == [
               [{:key, 1, :position, nil, ["message.position", "position"]}],
               []
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
    defmodule BuildProject do
      use Hologram.Entity

      relationship :members, [Hologram.PolicyTest.BuildMember], inverse: project

      allow :read, when: any(member <- members, member.user_id == user_id())
    end

    defmodule BuildMember do
      use Hologram.Entity

      relationship :project, BuildProject, optional: true
      relationship :user, Module14, optional: true

      allow :read
    end

    test "builds a quantifier written in a condition" do
      assert build(BuildProject) == %{
               read: [
                 %{
                   predicates: [{:any, {[:members], [{:user_id, :==, {:actor}}]}}],
                   to: nil,
                   via: nil
                 }
               ]
             }
    end

    test "returns empty map for entity type without policy declarations" do
      assert build(Module1) == %{}
    end

    test "builds rules per operation, keeping declaration order" do
      owner_rule = %{predicates: [], to: [{:own, [:owner]}], via: nil}
      archive_rule = %{predicates: [{:author_id, :==, {:actor}}], to: nil, via: nil}
      publish_rule = %{predicates: [], to: nil, via: {:publish, [:parent]}}

      assert build(Policy.Module1) == %{
               :archive => [archive_rule],
               :delete => [
                 %{predicates: [], to: [{:rel, [:parent], [:admin]}], via: nil}
               ],
               :grant_role => [owner_rule, owner_rule],
               :publish => [publish_rule],
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
               {:revoke_role, :owner} => [owner_rule],
               {:update, :author} => [archive_rule],
               {:update, :parent} => [publish_rule]
             }
    end

    test "keeps the operation a delegation names" do
      assert build(Policy.Module11) == %{
               create: [%{predicates: [], to: nil, via: {:update, [:parent]}}]
             }
    end

    test "follows a path in a condition, a delegation and a grant reference" do
      archive_rule = %{predicates: [{[:link, :priority], :==, :high}], to: nil, via: nil}
      publish_rule = %{predicates: [], to: nil, via: {:publish, [:parent, :parent]}}

      triage_rule = %{
        predicates: [{[:parent, :parent, :created_at], :>=, ~U[2026-01-01 00:00:00Z]}],
        to: nil,
        via: nil
      }

      assert build(Policy.Module12) == %{
               :archive => [archive_rule],
               :delete => [
                 %{
                   predicates: [{:level, :<=, {:attribute, [:parent, :parent, :priority]}}],
                   to: nil,
                   via: nil
                 }
               ],
               :publish => [publish_rule],
               :read => [
                 %{predicates: [{[:parent, :parent, :public], :==, true}], to: nil, via: nil}
               ],
               :triage => [triage_rule],
               :update => [
                 %{predicates: [], to: [{:rel, [:parent, :parent], [:viewer]}], via: nil}
               ],
               {:update, :level} => [triage_rule],
               {:update, :link} => [archive_rule, publish_rule]
             }
    end
  end

  describe "build/1 for named lines" do
    test "keys a named line under its name as well as its operation" do
      defmodule NamedUpdateLineFixture do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        role :owner

        allow :read
        allow :update, as: :archive, to: :owner, when: archived == false
      end

      archive_rule = %{predicates: [{:archived, :==, false}], to: [{:own, [:owner]}], via: nil}

      assert build(NamedUpdateLineFixture) == %{
               :archive => [archive_rule],
               :read => [%{predicates: [], to: nil, via: nil}],
               :update => [archive_rule]
             }
    end

    test "keys every line sharing a name under it, in declaration order" do
      defmodule SharedNameFixture do
        use Hologram.Entity

        role :admin
        role :owner

        allow :update, as: :archive, to: :owner
        allow :update, to: :admin
        allow :update, as: :archive, to: :admin, when: id != nil
      end

      owner_rule = %{predicates: [], to: [{:own, [:owner]}], via: nil}
      admin_rule = %{predicates: [], to: [{:own, [:admin]}], via: nil}
      conditional_admin_rule = %{predicates: [{:id, :!=, nil}], to: [{:own, [:admin]}], via: nil}

      assert build(SharedNameFixture) == %{
               :archive => [owner_rule, conditional_admin_rule],
               :update => [owner_rule, admin_rule, conditional_admin_rule]
             }
    end

    test "keys a named read line under its name, beside the read rules queries apply" do
      defmodule NamedReadLineFixture do
        use Hologram.Entity

        attribute :draft, :boolean, default: false

        allow :read, when: draft == false
        allow :read, as: :see_drafts, when: draft == true
      end

      draft_rule = %{predicates: [{:draft, :==, true}], to: nil, via: nil}

      assert build(NamedReadLineFixture) == %{
               :read => [%{predicates: [{:draft, :==, false}], to: nil, via: nil}, draft_rule],
               :see_drafts => [draft_rule]
             }
    end

    test "keys named create and delete lines under their names" do
      defmodule NamedCreateDeleteFixture do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        allow :create, as: :draft
        allow :delete, as: :purge, when: archived == true
      end

      purge_rule = %{predicates: [{:archived, :==, true}], to: nil, via: nil}

      assert build(NamedCreateDeleteFixture) == %{
               :create => [%{predicates: [], to: nil, via: nil}],
               :delete => [purge_rule],
               :draft => [%{predicates: [], to: nil, via: nil}],
               :purge => [purge_rule]
             }
    end

    # A bare grant line covers the roles its holders may hand out, and a type declaring none has
    # none to cover - so the line compiles to no rule, its name to no key, and can? answers no, as
    # it does for the same line unnamed.
    test "keys a named grant lifecycle line covering no role under no name" do
      defmodule UncoveringNamedGrantFixture do
        use Hologram.Entity

        allow :grant_role, as: :invite, to: Hologram.Test.Fixtures.Role.Module1
      end

      assert build(UncoveringNamedGrantFixture) == %{}
      assert :invite in operations(UncoveringNamedGrantFixture)
    end

    test "keys a named grant lifecycle line's per-role rules under its name, each once" do
      defmodule NamedGrantLineFixture do
        use Hologram.Entity

        role :editor
        role :owner, extends: :editor

        allow :grant_role, as: :invite, to: :owner
        allow {:grant_role, :editor}, as: :invite, to: :editor
      end

      owner_rule = %{predicates: [], to: [{:own, [:owner]}], via: nil}
      editor_rule = %{predicates: [], to: [{:own, [:editor, :owner]}], via: nil}

      assert build(NamedGrantLineFixture)[:invite] == [owner_rule, editor_rule]
    end
  end

  describe "build/1 for field-limited lines" do
    test "keys an only line under each field it lists, and not under :update" do
      defmodule OnlyLineFixture do
        use Hologram.Entity

        attribute :name, :string
        attribute :topic, :string

        role :member

        allow :read
        allow :update, to: :member, only: [:topic, :name]
      end

      member_rule = %{predicates: [], to: [{:own, [:member]}], via: nil}

      assert build(OnlyLineFixture) == %{
               :read => [%{predicates: [], to: nil, via: nil}],
               {:update, :name} => [member_rule],
               {:update, :topic} => [member_rule]
             }
    end

    test "keys a field listed twice once" do
      defmodule RepeatedFieldFixture do
        use Hologram.Entity

        attribute :topic, :string

        allow :update, only: [:topic, :topic]
      end

      assert build(RepeatedFieldFixture) == %{
               {:update, :topic} => [%{predicates: [], to: nil, via: nil}]
             }
    end

    test "keys an except line under every update field but the listed ones" do
      defmodule ExceptLineFixture do
        use Hologram.Entity

        attribute :name, :string
        attribute :topic, :string

        relationship :parent, Hologram.Test.Fixtures.Entity.Module1, optional: true
        relationship :tags, [Hologram.Test.Fixtures.Entity.Module2]

        allow :update, except: [:name]
      end

      rule = %{predicates: [], to: nil, via: nil}

      assert build(ExceptLineFixture) == %{
               {:update, :parent} => [rule],
               {:update, :tags} => [rule],
               {:update, :topic} => [rule]
             }
    end

    test "keys a named limited line under its name and its fields, beside a whole-row line" do
      defmodule NamedLimitedLineFixture do
        use Hologram.Entity

        attribute :archived, :boolean, default: false
        attribute :topic, :string

        role :member
        role :owner

        allow :update, to: :owner
        allow :update, as: :set_topic, to: :member, only: [:topic]
      end

      owner_rule = %{predicates: [], to: [{:own, [:owner]}], via: nil}
      member_rule = %{predicates: [], to: [{:own, [:member]}], via: nil}

      assert build(NamedLimitedLineFixture) == %{
               :set_topic => [member_rule],
               :update => [owner_rule],
               {:update, :topic} => [member_rule]
             }
    end
  end

  describe "field_rules/2" do
    test "returns a field's limited rules followed by the whole-row ones" do
      limited = %{predicates: [], to: [{:own, [:member]}], via: nil}
      whole = %{predicates: [], to: [{:own, [:owner]}], via: nil}
      policy = %{:update => [whole], {:update, :topic} => [limited]}

      assert field_rules(policy, :topic) == [limited, whole]
      assert field_rules(policy, :name) == [whole]
      assert field_rules(%{}, :name) == []
    end
  end

  describe "build/1 for lines reading the row after the change" do
    test "keeps the clauses under :exact and leaves the others in the predicates" do
      defmodule NewRowFixture1 do
        use Hologram.Entity

        attribute :status, :enum, values: [:approved, :pending], default: :pending

        role :manager

        allow :read

        allow :update,
          as: :approve,
          to: :manager,
          only: [:status],
          when: status == :pending and new(status) == :approved
      end

      assert build(NewRowFixture1)[:approve] == [
               %{
                 exact: %{
                   predicates: [
                     {:status, :==, :pending},
                     {{:outer, 1, :status}, :==, :approved}
                   ]
                 },
                 predicates: [{:status, :==, :pending}],
                 to: [{:own, [:manager]}],
                 via: nil
               }
             ]
    end

    test "leaves a rule with no new() without :exact" do
      defmodule NewRowFixture2 do
        use Hologram.Entity

        attribute :priority, :integer

        allow :read
        allow :update, when: priority > 1
      end

      assert build(NewRowFixture2)[:update] == [
               %{predicates: [{:priority, :>, 1}], to: nil, via: nil}
             ]
    end

    test "drops a disjunction with an alternative left with nothing" do
      defmodule NewRowFixture3 do
        use Hologram.Entity

        attribute :priority, :integer

        allow :read
        allow :update, when: priority == 1 or new(priority) == 2
      end

      assert [%{exact: %{predicates: [{:or, _alternatives}]}, predicates: []}] =
               build(NewRowFixture3)[:update]
    end

    test "keeps a disjunction whose alternatives each keep a clause" do
      defmodule NewRowFixture4 do
        use Hologram.Entity

        attribute :priority, :integer
        attribute :rank, :integer

        allow :read
        allow :update, when: (rank == 1 and new(priority) == 2) or priority == 3
      end

      assert [%{predicates: [{:or, [[{:rank, :==, 1}], [{:priority, :==, 3}]]}]}] =
               build(NewRowFixture4)[:update]
    end

    defmodule NewRowTag do
      use Hologram.Entity

      attribute :level, :integer

      allow :read
    end

    test "drops a quantifier reading the new row inside its condition whole" do
      defmodule NewRowFixture5 do
        use Hologram.Entity

        attribute :priority, :integer

        relationship :tags, [NewRowTag]

        allow :read
        allow :update, when: none(tag <- tags, tag.level > new(priority) and tag.level > 1)
      end

      assert [%{exact: %{predicates: [{:none, {[:tags], _clauses}}]}, predicates: []}] =
               build(NewRowFixture5)[:update]
    end

    test "drops a quantifier over a source on the new row" do
      defmodule NewRowFixture6 do
        use Hologram.Entity

        relationship :tags, [NewRowTag]

        allow :read
        allow :update, when: any(new(tags))
      end

      assert [%{exact: %{predicates: [{:any, {{:outer, 1, [:tags]}, []}}]}, predicates: []}] =
               build(NewRowFixture6)[:update]
    end

    test "keeps a quantifier reading only the stored row" do
      defmodule NewRowFixture7 do
        use Hologram.Entity

        attribute :priority, :integer

        relationship :tags, [NewRowTag]

        allow :read
        allow :update, when: any(tag <- tags, tag.level > priority) and new(priority) > 1
      end

      assert [%{predicates: [{:any, {[:tags], _clauses}}]}] = build(NewRowFixture7)[:update]
    end
  end

  describe "stored_spelling/1" do
    test "spells a name of the new row as the name of the rule's row" do
      assert stored_spelling([{{:outer, 1, :status}, :==, :approved}]) ==
               [{:status, :==, :approved}]
    end

    test "spells a path and an operand of the new row" do
      assert stored_spelling([
               {{:outer, 1, [:project, :rank]}, :>, {:attribute, {:outer, 1, :priority}}}
             ]) == [{[:project, :rank], :>, {:attribute, :priority}}]
    end

    test "spells a quantifier's source and leaves a name of the rule's row inside it" do
      clauses = [
        {:any,
         {{:outer, 1, [:project, :members]},
          [
            {:level, :>=, {:attribute, {:outer, 2, :priority}}},
            {:rank, :==, {:attribute, {:outer, 1, :rank}}}
          ]}}
      ]

      assert stored_spelling(clauses) == [
               {:any,
                {[:project, :members],
                 [
                   {:level, :>=, {:attribute, {:outer, 1, :priority}}},
                   {:rank, :==, {:attribute, {:outer, 1, :rank}}}
                 ]}}
             ]
    end

    test "spells the alternatives of a disjunction" do
      assert stored_spelling([{:or, [[{{:outer, 1, :a}, :==, 1}], [{:b, :==, 2}]]}]) ==
               [{:or, [[{:a, :==, 1}], [{:b, :==, 2}]]}]
    end
  end

  describe "update_fields/1" do
    test "returns the attributes and relationships, sorted" do
      defmodule UpdateFieldsFixture do
        use Hologram.Entity

        attribute :topic, :string

        relationship :parent, Hologram.Test.Fixtures.Entity.Module1, optional: true
        relationship :tags, [Hologram.Test.Fixtures.Entity.Module2]

        derived :shout, :string, fn topic -> topic <> "!" end
      end

      assert update_fields(UpdateFieldsFixture) == [:parent, :tags, :topic]
    end

    test "leaves out a job type's framework-owned attributes" do
      assert update_fields(Hologram.Test.Fixtures.Job.Module1) == []
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

    test "covers every declared role with a global holder" do
      defmodule GlobalHolderFixture do
        use Hologram.Entity

        role :owner
        role :viewer

        allow :grant_role, to: [:owner, Hologram.Test.Fixtures.Role.Module1]
      end

      global_reference = {:global, [Role.Module1, Role.Module2]}

      assert build(GlobalHolderFixture) == %{
               :grant_role => [
                 %{predicates: [], to: [{:own, [:owner]}, global_reference], via: nil},
                 %{predicates: [], to: [global_reference], via: nil}
               ],
               {:grant_role, :owner} => [
                 %{predicates: [], to: [{:own, [:owner]}, global_reference], via: nil}
               ],
               {:grant_role, :viewer} => [
                 %{predicates: [], to: [global_reference], via: nil}
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

        allow :update, as: :archive, to: Hologram.Test.Fixtures.Role.Module1
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
                   predicates: [{:entity_type, :==, Policy.Module1}],
                   to: [{:named, Policy.Module1, [:owner]}],
                   via: nil
                 },
                 %{
                   predicates: [{:entity_type, :==, Policy.Module2}],
                   to: [
                     {:named, Policy.Module2, [:admin, :member]},
                     {:global, [Role.Module1, Role.Module2]}
                   ],
                   via: nil
                 },
                 %{
                   predicates: [{:entity_type, :==, Policy.Module40}],
                   to: [{:named, Policy.Module40, [:owner]}],
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

  describe "deciding_quantifier?/3" do
    test "holds for a none and an all" do
      project = Hologram.PolicyTest.VerdictProject

      assert deciding_quantifier?(project, :update, {:none, {[:members], []}})
      assert deciding_quantifier?(project, :update, {:all, {[:members], [{:seat, :==, "full"}]}})
    end

    test "holds for an any holding a none in an alternative of its condition" do
      inner = [{:or, [[{:seat, :==, "full"}], [{:none, {{:outer, 1, [:labels]}, []}}]]}]

      assert deciding_quantifier?(
               Hologram.PolicyTest.VerdictProject,
               :update,
               {:any, {[:members], inner}}
             )
    end

    # A bounded set computed over the rows a client holds can hold rows the server's doesn't.
    test "holds for an any over a derived set" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.LockedBoard,
               :update,
               {:any, {[:top_cards], [{:rank, :==, 1}]}}
             )
    end

    test "holds for an any holding an any over a derived set" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.LockedTeam,
               :update,
               {:any, {[:boards], [{:any, {[:top_cards], []}}]}}
             )
    end

    test "holds for an any over a derived set past a relationship to its owner" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.TopCardsRule,
               :update,
               {:any, {[:board, :top_cards], []}}
             )
    end

    # The inner source is read on the board, one quantifier out, which holds the derived set.
    test "holds for an any holding an any over a derived set read on the row above" do
      clause = {:any, {[:cards], [{:any, {{:outer, 1, [:top_cards]}, []}}]}}

      assert deciding_quantifier?(Hologram.PolicyTest.LockedBoard, :update, clause)
    end

    test "fails for an any holding an any over a stored set read on the row above" do
      clause = {:any, {[:cards], [{:any, {{:outer, 1, [:cards]}, []}}]}}

      refute deciding_quantifier?(Hologram.PolicyTest.LockedBoard, :update, clause)
    end

    # A client can't compute the count.
    test "holds for an any whose condition reads a derived field counting a set" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.LockedBoard,
               :update,
               {:any, {[:cards], [{:tag_count, :<, 2}]}}
             )
    end

    # No client holds a server-only value, wherever the clause reads it.
    test "holds for a predicate on a server-only attribute" do
      report = Hologram.PolicyTest.ServerOnlyReport

      assert deciding_quantifier?(report, :update, {:reviewed, :==, true})
      assert deciding_quantifier?(report, :update, {:reviewed_on, :!=, nil})
    end

    test "holds for a predicate on a server-only attribute a path leads to" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.ServerOnlyComment,
               :update,
               {[:report, :reviewed], :==, true}
             )
    end

    test "holds for a predicate whose operand names a server-only attribute" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.ServerOnlyReport,
               :update,
               {:title, :==, {:attribute, :reviewed}}
             )
    end

    test "holds for an any whose condition reads a server-only attribute of the set's rows" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.ServerOnlyReport,
               :update,
               {:any, {[:comments], [{:flagged, :==, true}]}}
             )
    end

    test "holds for an any whose condition reads a server-only attribute of the row above" do
      clause = {:any, {[:comments], [{:body, :==, {:attribute, {:outer, 1, :reviewed}}}]}}

      assert deciding_quantifier?(Hologram.PolicyTest.ServerOnlyReport, :update, clause)
    end

    test "fails for a predicate on a stored attribute of a type with a server-only one" do
      refute deciding_quantifier?(
               Hologram.PolicyTest.ServerOnlyReport,
               :update,
               {:title, :==, "x"}
             )
    end

    test "fails for an any alone and for a predicate" do
      project = Hologram.PolicyTest.VerdictProject

      refute deciding_quantifier?(project, :update, {:any, {[:members], [{:seat, :==, "full"}]}})
      refute deciding_quantifier?(project, :update, {:seat, :==, "full"})
    end

    defmodule UnreadableProject do
      use Hologram.Entity

      attribute :archived, :boolean
      attribute :name, :string

      relationship :checks, [Hologram.PolicyTest.UnreadableCheck]

      allow :update
    end

    defmodule UnreadableCheck do
      use Hologram.Entity

      attribute :passed, :boolean

      allow :update
    end

    defmodule ReadableTag do
      use Hologram.Entity

      attribute :name, :string

      relationship :project, Hologram.PolicyTest.UnreadableProject, optional: true

      derived :project_open, :boolean, fn project -> project.archived == false end

      allow :read
    end

    defmodule UnreadableReadTask do
      use Hologram.Entity

      attribute :title, :string

      relationship :owner_tag, ReadableTag, optional: true
      relationship :parent, __MODULE__, optional: true
      relationship :project, UnreadableProject, optional: true
      relationship :tags, [ReadableTag]

      derived :project_open, :boolean, fn project -> project.archived == false end

      allow :read, when: project.archived == false
    end

    # No client holds a row of a type nobody may read, so only the server's verdict answers a read
    # rule reading one. Any other rule reading one fails the build.
    test "holds for a read rule's path to a type nobody may read" do
      clause = {[:project, :archived], :==, false}

      assert deciding_quantifier?(UnreadableReadTask, :read, clause)
      refute deciding_quantifier?(UnreadableReadTask, :update, clause)
    end

    test "holds for a read rule's operand path to a type nobody may read" do
      clause = {:title, :==, {:attribute, [:project, :name]}}

      assert deciding_quantifier?(UnreadableReadTask, :read, clause)
    end

    test "holds for a read rule's derived field reading a type nobody may read" do
      clause = {:project_open, :==, true}

      assert deciding_quantifier?(UnreadableReadTask, :read, clause)
      refute deciding_quantifier?(UnreadableReadTask, :update, clause)
    end

    test "holds for a read rule's any whose source runs through a type nobody may read" do
      clause = {:any, {[:project, :checks], [{:passed, :==, true}]}}

      assert deciding_quantifier?(UnreadableReadTask, :read, clause)
      refute deciding_quantifier?(UnreadableReadTask, :update, clause)
    end

    test "holds for a read rule's any whose condition reads a type nobody may read" do
      clause = {:any, {[:tags], [{[:project, :archived], :==, false}]}}

      assert deciding_quantifier?(UnreadableReadTask, :read, clause)
      refute deciding_quantifier?(UnreadableReadTask, :update, clause)
    end

    # Asked with no definition put, as the validator asks before the build resolves any.
    test "holds for a read rule's any whose condition reads a derived value reading a type nobody may read" do
      clause = {:any, {[:tags], [{:project_open, :==, true}]}}

      assert deciding_quantifier?(UnreadableReadTask, :read, clause)
      refute deciding_quantifier?(UnreadableReadTask, :update, clause)
    end

    test "holds for a read rule's any whose condition reads a type nobody may read off the row above" do
      clause = {:any, {[:tags], [{:name, :==, {:attribute, {:outer, 1, [:project, :name]}}}]}}

      assert deciding_quantifier?(UnreadableReadTask, :read, clause)
      refute deciding_quantifier?(UnreadableReadTask, :update, clause)
    end

    test "fails for a read rule's path through types someone may read" do
      refute deciding_quantifier?(UnreadableReadTask, :read, {[:owner_tag, :name], :==, "x"})
    end

    # Readers.Module24's project (Readers.Module23) has no read rule, and the team's id the role is
    # held on is read off it.
    test "holds for a read rule's role reference reading a type nobody may read" do
      item = {:to, {:rel, [:project, :team], [:member]}}

      assert deciding_quantifier?(Policy.Readers.Module24, :read, item)
      refute deciding_quantifier?(Policy.Readers.Module24, :update, item)
    end

    # The team's id is read off the task itself.
    test "fails for a role reference one relationship away" do
      refute deciding_quantifier?(
               Policy.Readers.Module24,
               :read,
               {:to, {:rel, [:team], [:member]}}
             )
    end

    # Readers.Module13's parent (Policy.Module1) has a read rule.
    test "fails for a role reference reading types someone may read" do
      item = {:to, {:rel, [:parent, :parent], [:member]}}

      refute deciding_quantifier?(Policy.Readers.Module13, :read, item)
    end

    test "fails for a role reference on the row itself" do
      refute deciding_quantifier?(Policy.Readers.Module24, :read, {:to, {:own, [:member]}})
    end

    # Readers.Module28's vault (Readers.Module25) has no read rule, so no client holds it.
    test "holds for a read rule's delegation to a type nobody may read" do
      item = {:via, {:update, [:vault]}}

      assert deciding_quantifier?(Policy.Readers.Module28, :read, item)
      refute deciding_quantifier?(Policy.Readers.Module28, :update, item)
    end

    # The crate is read through the shelf (Readers.Module27), which has no read rule.
    test "holds for a read rule's delegation through a type nobody may read" do
      assert deciding_quantifier?(
               Policy.Readers.Module28,
               :read,
               {:via, {:read, [:shelf, :crate]}}
             )
    end

    test "fails for a delegation through types someone may read" do
      refute deciding_quantifier?(Policy.Readers.Module28, :read, {:via, {:read, [:crate]}})
    end
  end

  describe "delegation/2" do
    test "returns nil for a line that delegates nothing" do
      assert delegation(:read, nil) == nil
    end

    test "asks the same operation through a relationship" do
      assert delegation(:read, :parent) == {:read, [:parent]}
    end

    test "asks the same operation through a path" do
      assert delegation(:read, [:trip, :user]) == {:read, [:trip, :user]}
    end

    test "keeps the operation a tuple names" do
      assert delegation(:create, {:update, :parent}) == {:update, [:parent]}
    end

    test "keeps the operation a tuple around a path names" do
      assert delegation(:create, {:update, [:stop, :trip]}) == {:update, [:stop, :trip]}
    end
  end

  describe "expand_global_role/1" do
    test "returns the module alone for a role no other module extends" do
      assert expand_global_role(Role.Module2) == [Role.Module2]
    end

    test "adds every module whose extends chain reaches the role, sorted" do
      assert expand_global_role(Role.Module1) == [Role.Module1, Role.Module2]
    end
  end

  describe "expand_global_role/2" do
    test "returns the module alone for a role no given module extends" do
      assert expand_global_role(Role.Module2, [Role.Module1, Role.Module2]) == [Role.Module2]
    end

    test "adds every given module whose extends chain reaches the role, sorted" do
      assert expand_global_role(Role.Module1, [Role.Module1, Role.Module2]) == [
               Role.Module1,
               Role.Module2
             ]
    end

    test "leaves out a module extending the role that is not among the given ones" do
      assert expand_global_role(Role.Module1, [Role.Module1]) == [Role.Module1]
    end
  end

  describe "framework_operations/0" do
    test "returns the four verbs' operations and the three gates, sorted" do
      assert framework_operations() == [
               :create,
               :delete,
               :grant_role,
               :read,
               :read_roles,
               :revoke_role,
               :update
             ]
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

  describe "hash/1" do
    defmodule HashedTask do
      use Hologram.Entity

      attribute :first, :string

      derived :label, :string, fn first -> first <> "!" end

      allow :read, when: label == "x"
    end

    defmodule HashedNote do
      use Hologram.Entity

      attribute :first, :string

      derived :label, :string, fn first -> first <> "!" end

      allow :read, when: first == "x"
    end

    defmodule HashedMember do
      use Hologram.Entity

      attribute :seat, :string

      relationship :archive, Hologram.PolicyTest.HashedProject, optional: true
      relationship :project, Hologram.PolicyTest.HashedProject, optional: true

      allow :read
    end

    test "gives the same types the same hash, in any order" do
      put_derived_definitions([HashedTask, HashedNote])

      assert hash([HashedTask, HashedNote]) == hash([HashedNote, HashedTask])
    end

    test "gives a type a new hash when its rules change" do
      narrow = """
      attribute :archived, :boolean
      attribute :public, :boolean

      allow :read, when: public == true and archived == false
      """

      wide = """
      attribute :archived, :boolean
      attribute :public, :boolean

      allow :read, when: public == true
      """

      assert hash_of_project(narrow) != hash_of_project(wide)
    end

    # Rules are OR'd, so lines written in another order decide the same thing.
    test "gives a type the same hash when its allow lines are reordered" do
      read_first = """
      attribute :public, :boolean

      allow :read, when: public == true
      allow :read, when: public == false
      """

      read_second = """
      attribute :public, :boolean

      allow :read, when: public == false
      allow :read, when: public == true
      """

      assert hash_of_project(read_first) == hash_of_project(read_second)
    end

    test "gives a type a new hash when a derived field its rules read changes" do
      put_derived_definitions([HashedTask])

      rules_hash = hash([HashedTask])

      Derived.put_definitions(%{{HashedTask, :label} => {:value, "y"}})

      assert hash([HashedTask]) != rules_hash
    end

    # An enum's values order what a comparison with one of them decides, whatever the body says.
    test "gives a type a new hash when the declaration of a derived field its rules read changes" do
      high_first = """
      attribute :score, :integer

      derived :rank, :enum, [values: [:high, :low]], fn score ->
        if score > 5, do: :high, else: :low
      end

      allow :read, when: rank > :high
      """

      low_first = String.replace(high_first, "[:high, :low]", "[:low, :high]")

      assert hash_of_project(high_first) != hash_of_project(low_first)
    end

    test "gives a type the same hash when a derived field no rule reads changes" do
      put_derived_definitions([HashedNote])

      rules_hash = hash([HashedNote])

      Derived.put_definitions(%{{HashedNote, :label} => {:value, "y"}})

      assert hash([HashedNote]) == rules_hash
    end

    test "gives a type a new hash when an inverse its rules walk changes" do
      through_project = """
      relationship :members, [Hologram.PolicyTest.HashedMember], inverse: project

      allow :read, when: any(member <- members, member.seat == "full")
      """

      through_archive = """
      relationship :members, [Hologram.PolicyTest.HashedMember], inverse: archive

      allow :read, when: any(member <- members, member.seat == "full")
      """

      assert hash_of_project(through_project) != hash_of_project(through_archive)
    end

    test "gives a type a new hash when an inverse a derived set its rules read walks changes" do
      through_project = """
      relationship :members, [Hologram.PolicyTest.HashedMember], inverse: project

      derived :full_members, [Hologram.PolicyTest.HashedMember], fn members ->
        filter(members, seat == "full")
      end

      allow :read, when: any(member <- full_members, member.seat == "full")
      """

      through_archive = String.replace(through_project, "inverse: project", "inverse: archive")

      assert hash_of_project(through_project) != hash_of_project(through_archive)
    end

    test "gives a type a new hash when an inverse a derived count its rules read walks changes" do
      through_project = """
      relationship :members, [Hologram.PolicyTest.HashedMember], inverse: project

      derived :member_count, :integer, fn members -> count(members) end

      allow :read, when: member_count > 0
      """

      through_archive = String.replace(through_project, "inverse: project", "inverse: archive")

      assert hash_of_project(through_project) != hash_of_project(through_archive)
    end

    # A derived query's filter can read the owning row, which sits above the rows the query reads.
    test "gives a type a new hash when an inverse a derived query reading the owning row walks changes" do
      through_project = """
      attribute :seats, :string

      relationship :members, [Hologram.PolicyTest.HashedMember], inverse: project

      derived :seated_count, :integer, fn members, seats ->
        members
        |> filter(seat == ^seats)
        |> count()
      end

      allow :read, when: seated_count > 0
      """

      through_archive = String.replace(through_project, "inverse: project", "inverse: archive")

      assert hash_of_project(through_project) != hash_of_project(through_archive)
    end

    # The raw form, since it's the only way a filter's name of the owning row reaches an inverse: the
    # quantifier's source is the owning row's alumni, read from inside the query over its members.
    test "gives a type a new hash when an inverse of the owning row a derived query's filter walks changes" do
      through_project = """
      relationship :alumni, [Hologram.PolicyTest.HashedMember], inverse: project
      relationship :members, [Hologram.PolicyTest.HashedMember], inverse: archive

      derived :alumni_count, :integer, fn members ->
        members
        |> filter(^[{:any, {{:outer, 1, [:alumni]}, [seat: "x"]}}])
        |> count()
      end

      allow :read, when: alumni_count > 0
      """

      through_archive =
        String.replace(
          through_project,
          "alumni, [Hologram.PolicyTest.HashedMember], inverse: project",
          "alumni, [Hologram.PolicyTest.HashedMember], inverse: archive"
        )

      assert hash_of_project(through_project) != hash_of_project(through_archive)
    end

    # A quantifier over a derived set reads its rows' own relationships too, past the definition.
    test "gives a type a new hash when an inverse a rule reads on a derived set's rows changes" do
      through_idol = """
      relationship :idol, Hologram.PolicyTest.HashedProject, optional: true
      relationship :parent, Hologram.PolicyTest.HashedProject, optional: true

      relationship :fans, [Hologram.PolicyTest.HashedProject], inverse: idol
      relationship :kids, [Hologram.PolicyTest.HashedProject], inverse: parent

      derived :first_kids, [Hologram.PolicyTest.HashedProject], fn kids -> take(kids, 2) end

      allow :read, when: any(kid <- first_kids, any(kid.fans))
      """

      through_parent = String.replace(through_idol, "inverse: idol", "inverse: parent")

      assert hash_of_project(through_idol) != hash_of_project(through_parent)
    end

    test "gives a type the same hash when an inverse no rule walks changes" do
      through_project = """
      attribute :public, :boolean

      relationship :members, [Hologram.PolicyTest.HashedMember], inverse: project

      allow :read, when: public == true
      """

      through_archive = """
      attribute :public, :boolean

      relationship :members, [Hologram.PolicyTest.HashedMember], inverse: archive

      allow :read, when: public == true
      """

      assert hash_of_project(through_project) == hash_of_project(through_archive)
    end
  end

  describe "what a rule reading the row after the change reads" do
    defmodule NewReadChannel do
      use Hologram.Entity

      attribute :archived, :boolean, default: false

      relationship :messages, [Hologram.PolicyTest.NewReadMessage], inverse: channel

      allow :read
    end

    defmodule NewReadMessage do
      use Hologram.Entity

      attribute :body, :string
      attribute :pinned, :boolean, default: false

      relationship :channel, NewReadChannel, optional: true

      derived :label, :string, fn body -> body <> "!" end

      allow :read

      allow :update,
        as: :pin,
        only: [:pinned],
        when: none(message <- new(channel.messages), message.pinned == true)

      allow :update, as: :move, only: [:channel], when: new(channel.archived) == false
      allow :update, as: :retitle, only: [:body], when: new(label) == "x!"
    end

    setup do
      put_derived_definitions([NewReadMessage])
    end

    test "counts the chains new() follows among the related chains" do
      assert related_chains(NewReadMessage) == [[:channel], [:channel, :messages]]
    end

    test "counts a path through new() among the chains a client holds" do
      assert held_chains(NewReadMessage, :move) == [[:channel]]
    end

    # A none is one the rows a client holds can't answer.
    test "leaves a deciding quantifier over new() out of the chains a client holds" do
      assert held_chains(NewReadMessage, :pin) == []
    end

    test "names the set a none over new() reads among the locked links" do
      assert locked_set_links([NewReadMessage]) ==
               MapSet.new([{:reference, NewReadMessage, :channel_id, NewReadChannel}])
    end

    test "gives a type a new hash when a derived field only new() reads changes" do
      rules_hash = hash([NewReadMessage])

      Derived.put_definitions(%{{NewReadMessage, :label} => {:value, "y"}})

      assert hash([NewReadMessage]) != rules_hash
    end
  end

  describe "held_chains/2" do
    defmodule HeldTask do
      use Hologram.Entity

      relationship :project, Hologram.PolicyTest.VerdictProject, optional: true

      allow :update, via: project
    end

    test "returns the chains an any reads" do
      assert held_chains(Hologram.PolicyTest.VerdictProject, :read) == [[:members]]
    end

    # The server's verdict answers the all over the members as stored.
    test "leaves out the chains a deciding quantifier in an alternative reads" do
      assert held_chains(Hologram.PolicyTest.VerdictProject, :update) == []
    end

    test "returns a delegation's chain without the chains its deciding quantifiers read" do
      assert held_chains(HeldTask, :update) == [[:project]]
    end

    # The server's verdict answers the path over the project as stored.
    test "leaves out the chain a read rule reads through a type nobody may read" do
      assert held_chains(Hologram.PolicyTest.UnreadableReadTask, :read) == []
    end

    # The team's id is read off the project, which has no read rule, so the server's verdict answers
    # the reference.
    test "leaves out the chain a read rule's role reference reads through a type nobody may read" do
      assert related_chains(Policy.Readers.Module24, :read) == [[:project]]
      assert held_chains(Policy.Readers.Module24, :read) == []
    end

    # The vault and the shelf have no read rule, so the server's verdicts answer the delegations
    # through them, while the crate is read through readable types alone.
    test "leaves out the chains of a read rule's delegations through a type nobody may read" do
      assert related_chains(Policy.Readers.Module28, :read) == [
               [:crate],
               [:shelf, :crate],
               [:vault]
             ]

      assert held_chains(Policy.Readers.Module28, :read) == [[:crate]]
    end

    defmodule HeldOwner do
      use Hologram.Entity

      attribute :name, :string
    end

    defmodule HeldSeat do
      use Hologram.Entity

      attribute :taken, :boolean

      relationship :tags, [Hologram.PolicyTest.HeldOwner]
    end

    defmodule HeldBoard do
      use Hologram.Entity

      attribute :name, :string

      relationship :owner, HeldOwner, optional: true
      relationship :seats, [HeldSeat]

      allow :update, when: owner.name == "x" or all(seat <- seats, seat.taken == true)

      allow :delete,
        when: none(seat <- seats, seat.taken == true) and any(seat <- seats, seat.taken == false)

      allow :update,
        as: :archive,
        only: [:name],
        when: any(seat <- seats, none(tag <- seat.tags, tag.name == "x"))
    end

    defmodule HeldRoom do
      use Hologram.Entity

      relationship :board, HeldBoard, optional: true

      allow :update, when: board.name == "x" and none(seat <- board.seats, seat.taken == true)
    end

    test "returns the chain another alternative reads beside a deciding quantifier's" do
      assert held_chains(HeldBoard, :update) == [[:owner]]
    end

    test "returns a set a deciding quantifier reads that an any beside it reads too" do
      assert held_chains(HeldBoard, :delete) == [[:seats]]
    end

    test "leaves out the chains of an any holding a none" do
      assert held_chains(HeldBoard, :archive) == []
    end

    test "returns a row a path reads that a deciding quantifier reads a set through too" do
      assert held_chains(HeldRoom, :update) == [[:board]]
    end
  end

  describe "line_held_chains/2" do
    defmodule LineHeldOwner do
      use Hologram.Entity

      attribute :name, :string

      allow :read
    end

    defmodule LineHeldBanner do
      use Hologram.Entity

      attribute :title, :string

      relationship :owner, Hologram.PolicyTest.LineHeldOwner, optional: true

      allow :update, only: [:title]
      allow :update, except: [:owner], when: owner.name == "x"
    end

    test "tells apart the lines sharing a field's key" do
      [plain_line, reading_line] = LineHeldBanner.__policies__()

      assert held_chains(LineHeldBanner, {:update, :title}) == [[:owner]]
      assert line_held_chains(LineHeldBanner, plain_line) == []
      assert line_held_chains(LineHeldBanner, reading_line) == [[:owner]]
    end

    test "returns a delegation's chain" do
      [line] = HeldTask.__policies__()

      assert line_held_chains(HeldTask, line) == [[:project]]
    end

    test "leaves out the chains of a deciding quantifier" do
      [_update_line, _delete_line, archive_line] = HeldBoard.__policies__()

      assert line_held_chains(HeldBoard, archive_line) == []
    end
  end

  describe "locked_set_links/1" do
    defmodule LockedProject do
      use Hologram.Entity

      relationship :labels, [Hologram.PolicyTest.LockedLabel]
      relationship :members, [Hologram.PolicyTest.LockedMember], inverse: project

      allow :delete, when: none(members)
      allow :update, when: all(label <- labels, label.name == "ok")
    end

    defmodule LockedMember do
      use Hologram.Entity

      relationship :project, LockedProject, optional: true

      allow :read
    end

    defmodule LockedLabel do
      use Hologram.Entity

      attribute :name, :string

      relationship :projects, [LockedProject], inverse: labels

      allow :delete, when: none(projects)
    end

    defmodule LockedTask do
      use Hologram.Entity

      attribute :title, :string

      relationship :project, LockedProject, optional: true

      allow :update,
        when: title == "draft" or any(label <- project.labels, none(project.members))
    end

    defmodule AnyInNoneTask do
      use Hologram.Entity

      relationship :project, LockedProject, optional: true

      allow :update,
        when: none(label <- project.labels, any(project.members))
    end

    defmodule NoneInNoneTask do
      use Hologram.Entity

      relationship :project, LockedProject, optional: true

      allow :update, when: none(label <- project.labels, none(label.projects))
    end

    defmodule AnyProject do
      use Hologram.Entity

      relationship :members, [Hologram.PolicyTest.AnyMember], inverse: project

      allow :read, when: any(members)
    end

    defmodule AnyMember do
      use Hologram.Entity

      relationship :project, AnyProject, optional: true

      allow :read
    end

    test "names how a row joins a set a none or an all reads" do
      assert locked_set_links([LockedProject, LockedMember, LockedLabel]) ==
               MapSet.new([
                 {:edge, LockedProject, :labels, :source, LockedProject},
                 {:edge, LockedProject, :labels, :target, LockedLabel},
                 {:reference, LockedMember, :project_id, LockedProject}
               ])
    end

    # A label joining the project can only make the any true, which never refuses what it granted,
    # but a member joining the set the none reads on the task's project can make the none false. A
    # label has no project of its own, so the none's source is read on the task.
    test "names the set of a none inside an any's condition, in an alternative, through a relationship" do
      assert locked_set_links([LockedTask]) ==
               MapSet.new([{:reference, LockedMember, :project_id, LockedProject}])
    end

    # Inside the none the any's truth hurts, so a member joining the set it reads on the task's
    # project can refuse, as a label joining the none's own set can.
    test "names the set of an any inside a none" do
      assert locked_set_links([AnyInNoneTask]) ==
               MapSet.new([
                 {:edge, LockedProject, :labels, :source, LockedProject},
                 {:reference, LockedMember, :project_id, LockedProject}
               ])
    end

    # The inner none's truth hurts the outer one, so a project joining a label's set can only make
    # the inner none false and the outer none truer.
    test "leaves out the set of a none inside a none" do
      assert locked_set_links([NoneInNoneTask]) ==
               MapSet.new([{:edge, LockedProject, :labels, :source, LockedProject}])
    end

    test "leaves out a set read by an any alone" do
      assert locked_set_links([AnyProject, AnyMember]) == MapSet.new()
    end

    defmodule LockedBoard do
      use Hologram.Entity

      relationship :cards, [Hologram.PolicyTest.LockedCard], inverse: board
      relationship :labels, [Hologram.PolicyTest.LockedTag]
      relationship :team, Hologram.PolicyTest.LockedTeam, optional: true

      derived :busy_cards, [Hologram.PolicyTest.LockedCard], fn cards ->
        filter(cards, tag_count > 1)
      end

      derived :flagged_cards, [Hologram.PolicyTest.LockedCard], fn cards ->
        filter(cards, any(tag <- tags, tag.name == "flag"))
      end

      derived :label_count, :integer, fn labels -> count(labels) end

      derived :low_top_cards, [Hologram.PolicyTest.LockedCard], fn top_cards ->
        filter(top_cards, rank < 3)
      end

      derived :most_tagged_cards, [Hologram.PolicyTest.LockedCard], fn cards ->
        cards
        |> sort(tag_count: :desc)
        |> take(1)
      end

      derived :picked_cards, [Hologram.PolicyTest.LockedCard], fn cards, label_count ->
        if label_count > 1, do: take(cards, 1), else: cards
      end

      derived :top_cards, [Hologram.PolicyTest.LockedCard], fn cards ->
        cards
        |> sort(rank: :desc)
        |> take(2)
      end
    end

    defmodule LockedCard do
      use Hologram.Entity

      attribute :rank, :integer

      relationship :board, LockedBoard, optional: true
      relationship :tags, [Hologram.PolicyTest.LockedTag]

      derived :tag_count, :integer, fn tags -> count(tags) end
    end

    defmodule LockedTag do
      use Hologram.Entity

      attribute :name, :string
    end

    defmodule LockedTeam do
      use Hologram.Entity

      relationship :boards, [LockedBoard], inverse: team

      allow :update, when: any(card <- boards.top_cards, card.rank == 1)
    end

    defmodule BusyCardsRule do
      use Hologram.Entity

      relationship :board, LockedBoard, optional: true

      allow :update, when: any(card <- board.busy_cards, card.rank == 1)
    end

    defmodule CountedTagsRule do
      use Hologram.Entity

      relationship :board, LockedBoard, optional: true

      allow :update, when: any(card <- board.cards, card.tag_count < 2)
    end

    defmodule FlaggedCardsRule do
      use Hologram.Entity

      relationship :board, LockedBoard, optional: true

      allow :update, when: any(card <- board.flagged_cards, card.rank == 1)
    end

    defmodule LowTopCardsRule do
      use Hologram.Entity

      relationship :board, LockedBoard, optional: true

      allow :update, when: any(card <- board.low_top_cards, card.rank == 1)
    end

    defmodule MostTaggedCardsRule do
      use Hologram.Entity

      relationship :board, LockedBoard, optional: true

      allow :update, when: any(card <- board.most_tagged_cards, card.rank == 1)
    end

    defmodule PickedCardsRule do
      use Hologram.Entity

      relationship :board, LockedBoard, optional: true

      allow :update, when: any(card <- board.picked_cards, card.rank == 1)
    end

    defmodule TopCardsRule do
      use Hologram.Entity

      relationship :board, LockedBoard, optional: true

      allow :update, when: any(card <- board.top_cards, card.rank == 1)
    end

    setup do
      put_derived_definitions([LockedBoard, LockedCard])
    end

    # A card joining the board can push another out of its bound, so even an any over the set can
    # turn false.
    test "names how a row joins the set a derived set reads, under an any" do
      assert locked_set_links([TopCardsRule]) ==
               MapSet.new([{:reference, LockedCard, :board_id, LockedBoard}])
    end

    test "names how a row joins the set a derived set built on another one reads" do
      assert locked_set_links([LowTopCardsRule]) ==
               MapSet.new([{:reference, LockedCard, :board_id, LockedBoard}])
    end

    # A board joining the team brings its cards into the set the quantifier reads.
    test "names how a row joins a set the relationships before a derived set read" do
      assert locked_set_links([LockedTeam]) ==
               MapSet.new([
                 {:reference, LockedBoard, :team_id, LockedTeam},
                 {:reference, LockedCard, :board_id, LockedBoard}
               ])
    end

    # A tag joining a card can take it into the set or out of it, whichever way the filter's any
    # points.
    test "names the set a quantifier in a derived set's filter reads" do
      assert locked_set_links([FlaggedCardsRule]) ==
               MapSet.new([
                 {:edge, LockedCard, :tags, :source, LockedCard},
                 {:reference, LockedCard, :board_id, LockedBoard}
               ])
    end

    # A tag joining a card moves its count, which takes it into the set or out of it.
    test "names the set a derived field read in a derived set's filter reads" do
      assert locked_set_links([BusyCardsRule]) ==
               MapSet.new([
                 {:edge, LockedCard, :tags, :source, LockedCard},
                 {:reference, LockedCard, :board_id, LockedBoard}
               ])
    end

    # A tag joining a card moves its count, which reorders the set the bound is taken from.
    test "names the set a derived sort key reads" do
      assert locked_set_links([MostTaggedCardsRule]) ==
               MapSet.new([
                 {:edge, LockedCard, :tags, :source, LockedCard},
                 {:reference, LockedCard, :board_id, LockedBoard}
               ])
    end

    # A label joining the board can flip which query the if picks.
    test "names the set a derived set's if condition reads" do
      assert locked_set_links([PickedCardsRule]) ==
               MapSet.new([
                 {:edge, LockedBoard, :labels, :source, LockedBoard},
                 {:reference, LockedCard, :board_id, LockedBoard}
               ])
    end

    # The any over the board's own cards names nothing, but the count a card's condition compares
    # can be compared either way.
    test "names the set a derived field in a quantifier's condition reads" do
      assert locked_set_links([CountedTagsRule]) ==
               MapSet.new([{:edge, LockedCard, :tags, :source, LockedCard}])
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

  describe "operation_reads/2" do
    # The close rule of the vault holds a role on it, and the crate delegation reads no type nobody
    # may read.
    test "returns the types the delegations read, deciding or not, the grant store among them" do
      assert operation_reads(Policy.Readers.Module28, :read) == [
               RoleGrant,
               Policy.Readers.Module25,
               Policy.Readers.Module26,
               Policy.Readers.Module27
             ]
    end

    test "returns the grant store and the rows before a role reference's last relationship" do
      assert operation_reads(Policy.Readers.Module24, :read) == [
               RoleGrant,
               Policy.Readers.Module23
             ]
    end

    test "returns a quantifier's own type beside its set's" do
      assert operation_reads(VerdictProject, :delete) == [VerdictLabel, VerdictProject]
    end

    test "returns what a rule with no deciding item reads" do
      assert operation_reads(VerdictProject, :read) == [VerdictMember, VerdictProject]
    end

    # The limited line reads the members, and the whole-row one the labels.
    test "returns what the limited lines and the whole-row ones read for a field of an update" do
      assert operation_reads(Hologram.PolicyTest.FieldVerdictProject, {:update, :name}) == [
               Hologram.PolicyTest.FieldVerdictProject,
               VerdictLabel,
               VerdictMember
             ]
    end
  end

  describe "operation_rules/2" do
    test "returns the limited lines and the whole-row ones for a field of an update" do
      policy = %{:update => [:whole_row], {:update, :name} => [:limited]}

      assert operation_rules(policy, {:update, :name}) == [:limited, :whole_row]
    end

    test "returns an operation's own rules" do
      policy = %{:delete => [:delete], {:grant_role, :editor} => [:grant]}

      assert operation_rules(policy, :delete) == [:delete]
      assert operation_rules(policy, {:grant_role, :editor}) == [:grant]
    end

    test "returns no rules for an operation the policy has none for" do
      assert operation_rules(%{}, :delete) == []
    end
  end

  describe "operations/1" do
    test "returns the names the allow lines carry beside the framework's operations" do
      defmodule NamedOperationsFixture do
        use Hologram.Entity

        allow :update, as: :archive
        allow :delete, as: :purge
      end

      assert operations(NamedOperationsFixture) == [
               :archive,
               :create,
               :delete,
               :grant_role,
               :purge,
               :read,
               :read_roles,
               :revoke_role,
               :update
             ]
    end

    test "returns the framework's operations alone for an entity type declaring nothing" do
      assert operations(Module1) == framework_operations()
    end

    test "returns the framework's operations alone for the grant store" do
      assert operations(RoleGrant) == framework_operations()
    end

    test "includes a name carried by a line taken from a policy module" do
      defmodule TakenOperationPolicyFixture do
        use Hologram.Policy

        allow :update, as: :publish, when: public == true
      end

      defmodule TakenOperationEntityFixture do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        policy TakenOperationPolicyFixture
      end

      assert :publish in operations(TakenOperationEntityFixture)
    end

    test "names a per-role line's operation once" do
      defmodule PerRoleLineEntityFixture do
        use Hologram.Entity

        role :editor
        role :owner

        allow {:grant_role, :editor}, to: :owner
        allow {:revoke_role, [:editor, :owner]}, to: :owner
      end

      assert operations(PerRoleLineEntityFixture) == framework_operations()
    end
  end

  describe "read_roles_qualifying_role_modules/1" do
    test "returns the expanded role modules holding a grant lifecycle gate" do
      assert read_roles_qualifying_role_modules(Policy.Module2) == [Role.Module1, Role.Module2]
    end

    test "returns empty list when no gate names a role module" do
      assert read_roles_qualifying_role_modules(Policy.Module1) == []
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

  describe "readable_type?/1" do
    test "holds for a type with a read rule" do
      assert readable_type?(Hologram.PolicyTest.ReadableTag)
    end

    test "fails for a type with no read rule" do
      refute readable_type?(Hologram.PolicyTest.UnreadableProject)
    end

    # The framework supplies the grant store's read rules.
    test "holds for the grant store" do
      assert readable_type?(RoleGrant)
    end
  end

  describe "readable_prefix/2" do
    # Module43 (the vault) has no read rule.
    test "stops a chain before its first type no session may read" do
      assert readable_prefix(Policy.Module45, [:shelf, :vault, :owner]) == [:shelf]
    end

    test "keeps a chain through readable types whole" do
      assert readable_prefix(Policy.Module45, [:shelf]) == [:shelf]
    end

    test "keeps nothing of a chain whose first hop is to a type no session may read" do
      assert readable_prefix(Policy.Module44, [:vault, :owner]) == []
    end
  end

  describe "related_chains/1" do
    # [:parent] is the role reference's chain without its last relationship - the id it holds is
    # read off the row before it. The third hop is the publish delegation's: the row two
    # relationships away delegates its own publish rule to its parent.
    test "returns the rows a path in a condition reads" do
      assert related_chains(Policy.Module12) == [
               [:link],
               [:parent],
               [:parent, :parent],
               [:parent, :parent, :parent]
             ]
    end

    test "reads no row through a role reference one relationship away" do
      assert related_chains(Policy.Module13) == []
    end

    # Each chain has one source: the path compared against, the path inside an alternative, and a
    # delegation to an operation its target declares no rule for, which reads the row it leads to
    # and nothing through it.
    test "returns the rows an operand path, an alternative and a ruleless delegation read" do
      assert related_chains(Policy.Module14) == [[:group], [:owner], [:peer]]
    end

    test "returns the row a delegation leads to" do
      assert related_chains(Policy.Module1) == [[:parent]]
    end

    test "returns the rows a derived field in a condition reads through its definition" do
      assert related_chains(Module42) == [[:note]]
    end

    test "follows a delegation into the rows its target's rules read" do
      assert related_chains(Policy.Module8) == [[:parent], [:parent, :parent]]
    end

    # The parent's update rule reads only the parent's own attribute, so the self-reference ends at
    # the row it delegates to.
    test "ends a delegation to the type itself at the row it leads to" do
      assert related_chains(Policy.Module9) == [[:parent]]
    end

    test "returns no chains for a type whose rules read only its own rows" do
      assert related_chains(Policy.Module7) == []
    end

    test "returns no chains for the grant store" do
      assert related_chains(RoleGrant) == []
    end
  end

  describe "related_chains/1 - quantifiers" do
    defmodule ChainProject do
      use Hologram.Entity

      relationship :labels, [Hologram.PolicyTest.ChainLabel]
      relationship :members, [Hologram.PolicyTest.ChainMember], inverse: project

      derived :first_members, [Hologram.PolicyTest.ChainMember], fn members ->
        take(members, 2)
      end

      allow :read, when: any(member <- members, member.seat == "full")
      allow :update, when: any(labels)

      allow :update,
        as: :archive,
        only: [:labels],
        when: any(member <- first_members, member.seat == "full")
    end

    defmodule ChainBoard do
      use Hologram.Entity

      attribute :public, :boolean

      relationship :projects, [ChainProject]

      allow :read, when: public == true or any(project <- projects, any(project.labels))
    end

    defmodule ChainMember do
      use Hologram.Entity

      attribute :seat, :string

      relationship :project, ChainProject, optional: true
      relationship :user, Module14, optional: true

      allow :read
    end

    defmodule ChainLabel do
      use Hologram.Entity

      attribute :name, :string

      allow :read
    end

    defmodule ChainTask do
      use Hologram.Entity

      relationship :project, ChainProject, optional: true

      allow :read, when: any(member <- project.members, member.user.email == "a")
      allow :update, via: project
    end

    # The labels are read for whether the project has any, so the set comes along though the
    # condition reads nothing on it.
    test "returns the sets a quantifier reads, with a condition and without one" do
      assert related_chains(ChainProject, :read) == [[:members]]
      assert related_chains(ChainProject, :update) == [[:labels]]
    end

    # The browser answers a quantifier over a derived set from the server's verdict, so none of its
    # rows are needed.
    test "leaves out a set a derived field holds" do
      assert related_chains(ChainProject, :archive) == []
    end

    test "returns the sets of a quantifier in an alternative and of one nested in its condition" do
      assert related_chains(ChainBoard) == [[:projects], [:projects, :labels]]
    end

    # A chain is followed hop by hop, so the project along the way comes with the members.
    test "returns the rows along a quantifier's source and a path from the set's rows" do
      assert related_chains(ChainTask, :read) == [
               [:project, :members],
               [:project, :members, :user]
             ]
    end

    test "returns a delegated rule's sets prefixed with the delegation's chain" do
      assert related_chains(ChainTask, :update) == [[:project], [:project, :labels]]
    end
  end

  describe "related_chains/2" do
    defmodule BuilderOwner do
      use Hologram.Entity

      alias Hologram.Test.Fixtures.Entity.Module36

      relationship :memberships, [Module36]

      allow :update, when: any(membership <- memberships, membership.unread_count > 0)
    end

    test "returns the rows the given operation's rules read" do
      assert related_chains(Policy.Module12, :delete) == [[:parent, :parent]]
    end

    # The row two relationships away delegates its own publish rule to its parent in turn.
    test "returns the rows a delegation reads under the operation it asks" do
      assert related_chains(Policy.Module12, :publish) == [
               [:parent, :parent],
               [:parent, :parent, :parent]
             ]
    end

    test "returns no chains for an operation with no rules" do
      assert related_chains(Policy.Module12, :create) == []
    end

    # The server's verdict answers the any, and the builder reads a set the browser never holds.
    test "returns a quantifier's set and nothing through a derived value calling a query builder" do
      assert related_chains(BuilderOwner, :update) == [[:memberships]]
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

  describe "validate_operation!/2" do
    defmodule FieldlessFixture do
      use Hologram.Entity

      allow :read
    end

    test "passes every framework operation on an entity type declaring nothing" do
      Enum.each(framework_operations(), fn operation ->
        assert validate_operation!(Module1, operation) == :ok
      end)
    end

    test "passes a name an allow line on the entity type carries" do
      defmodule NamedOperationFixture do
        use Hologram.Entity

        allow :update, as: :archive
      end

      assert validate_operation!(NamedOperationFixture, :archive) == :ok
    end

    test "passes a role tuple naming a role the entity type declares" do
      assert validate_operation!(Policy.Module1, {:grant_role, :editor}) == :ok
      assert validate_operation!(Policy.Module1, {:revoke_role, :viewer}) == :ok
    end

    test "passes an update tuple naming a field an update of the entity type sets" do
      assert validate_operation!(Policy.Module1, {:update, :public}) == :ok
      assert validate_operation!(Policy.Module1, {:update, :parent}) == :ok
    end

    test "passes an update tuple naming a list of fields an update of the entity type sets" do
      assert validate_operation!(Policy.Module1, {:update, [:public, :parent]}) == :ok
    end

    test "raises on an update tuple naming a field no update of the entity type sets" do
      expected_msg =
        "unknown field :parent_id in {:update, :parent_id} for Hologram.Test.Fixtures.Policy.Module1 - the fields an update sets are :author, :parent, :priority, :public"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:update, :parent_id})
      end
    end

    test "raises on an update list naming a field no update of the entity type sets" do
      expected_msg =
        "unknown field :updated_at in {:update, [:public, :updated_at]} for Hologram.Test.Fixtures.Policy.Module1 - the fields an update sets are :author, :parent, :priority, :public"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:update, [:public, :updated_at]})
      end
    end

    test "raises on an update tuple naming a field that is neither an atom nor a list" do
      expected_msg =
        ~s(unknown operation {:update, "public"} for Hologram.Test.Fixtures.Policy.Module1 - the operation tuples are {:grant_role, role}, {:revoke_role, role}, {:update, field} and {:update, fields})

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:update, "public"})
      end
    end

    test "raises on an update tuple naming an improper list" do
      expected_msg =
        "unknown operation {:update, [:public | :parent]} for Hologram.Test.Fixtures.Policy.Module1 - the operation tuples are {:grant_role, role}, {:revoke_role, role}, {:update, field} and {:update, fields}"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, wrap_term({:update, [:public | :parent]}))
      end
    end

    test "raises on an update list naming no field" do
      expected_msg =
        "unknown operation {:update, []} for Hologram.Test.Fixtures.Policy.Module1 - {:update, fields} names at least one field"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:update, []})
      end
    end

    test "raises on an update tuple naming a job's framework attribute" do
      expected_msg =
        "unknown field :status in {:update, :status} for Hologram.Test.Fixtures.Job.Module3 - the fields an update sets are :outcome"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Hologram.Test.Fixtures.Job.Module3, {:update, :status})
      end
    end

    test "raises on an update tuple for an entity type no update sets a field of" do
      expected_msg =
        "unknown field :title in {:update, :title} for Hologram.PolicyTest.FieldlessFixture - it has no field an update sets"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(FieldlessFixture, {:update, :title})
      end
    end

    test "raises on an operation no allow line on the entity type names" do
      expected_msg =
        "unknown operation :pin for Hologram.Test.Fixtures.Policy.Module1 - the framework's operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update, and its allow lines carry the names :archive and :publish"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, :pin)
      end
    end

    test "raises on an operation for an entity type whose allow lines carry no name" do
      expected_msg =
        "unknown operation :archive for Hologram.Test.Fixtures.Entity.Module1 - the framework's operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update, and its allow lines carry no name"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Module1, :archive)
      end
    end

    test "names a single name without a conjunction" do
      expected_msg =
        "unknown operation :publish for Hologram.Test.Fixtures.Policy.Module4 - the framework's operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update, and its allow lines carry the name :archive"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module4, :publish)
      end
    end

    test "raises on a role tuple naming a role the entity type does not declare" do
      expected_msg =
        "unknown role :editr in {:grant_role, :editr} for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:grant_role, :editr})
      end
    end

    test "raises on a role tuple for an entity type declaring no role" do
      expected_msg =
        "unknown role :editor in {:revoke_role, :editor} for Hologram.Test.Fixtures.Entity.Module1 - it declares no role"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Module1, {:revoke_role, :editor})
      end
    end

    test "raises on a tuple whose name is not a grant lifecycle operation" do
      expected_msg =
        "unknown operation {:publish, :editor} for Hologram.Test.Fixtures.Policy.Module1 - the operation tuples are {:grant_role, role}, {:revoke_role, role}, {:update, field} and {:update, fields}"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:publish, :editor})
      end
    end

    test "raises on a tuple that is not a pair" do
      expected_msg =
        "unknown operation {:grant_role, :editor, :extra} for Hologram.Test.Fixtures.Policy.Module1 - the operation tuples are {:grant_role, role}, {:revoke_role, role}, {:update, field} and {:update, fields}"

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:grant_role, :editor, :extra})
      end
    end

    test "raises on an operation that is neither an atom nor a tuple" do
      expected_msg =
        ~s(unknown operation "read" for Hologram.Test.Fixtures.Policy.Module1 - an entity operation is an atom, {:grant_role, role} / {:revoke_role, role} or {:update, field} / {:update, fields})

      assert_error MisuseError, expected_msg, fn ->
        validate_operation!(Policy.Module1, wrap_term("read"))
      end
    end
  end

  describe "verdict_key/2" do
    defmodule SharedFieldProject do
      use Hologram.Entity

      attribute :name, :string
      attribute :summary, :string
      attribute :title, :string

      relationship :labels, [Hologram.PolicyTest.VerdictLabel]

      allow :update, except: [:name], when: none(labels)
    end

    defmodule KeyedParcel do
      use Hologram.Entity

      relationship :vault, Hologram.PolicyTest.KeyedVault, optional: true

      allow :read, via: {:update, vault}
    end

    defmodule KeyedBoard do
      use Hologram.Entity

      relationship :cards, [Hologram.PolicyTest.KeyedCard]

      derived :top_cards, [Hologram.PolicyTest.KeyedCard], fn cards -> take(cards, 2) end

      allow :delete, when: any(card <- top_cards, card.rank == 1)
    end

    defmodule KeyedCard do
      use Hologram.Entity

      attribute :rank, :integer
    end

    defmodule ScoredBoard do
      use Hologram.Entity

      relationship :cards, [Hologram.PolicyTest.ScoredCard]

      derived :top_cards, [Hologram.PolicyTest.ScoredCard], fn cards ->
        cards
        |> sort(score: :desc)
        |> take(2)
      end

      allow :delete, when: any(card <- top_cards, card.rank == 1)
    end

    defmodule ScoredCard do
      use Hologram.Entity

      attribute :rank, :integer

      derived :score, :integer, fn rank -> rank end
    end

    defmodule LabelledMember do
      use Hologram.Entity

      attribute :first, :string

      derived :label, :string, fn first -> first <> "!" end

      allow :update, when: first == "x"
      allow :delete, when: label == "x"
    end

    defmodule RelabelledMember do
      use Hologram.Entity

      attribute :first, :string

      derived :label, :string, fn first -> first <> "?" end

      allow :update, when: first == "x"
      allow :delete, when: label == "x"
    end

    # Verdicts are stored with the rows a client holds, so the key an operation gets is pinned - a
    # change to how keys are made would leave every stored verdict unread.
    test "keys an operation by its key and a digest of its rules" do
      assert verdict_key(VerdictProject, :delete) == "delete:890acc79709b7822"
    end

    test "gives another operation another key" do
      assert verdict_key(VerdictProject, :archive) != verdict_key(VerdictProject, :delete)
    end

    # The whole-row rules are never a field's, which adds the lines covering it.
    test "keys a field of an update under update, apart from the whole row" do
      assert "update:" <> digest = verdict_key(VerdictProject, {:update, :name})

      refute String.contains?(digest, ":")
      assert verdict_key(VerdictProject, {:update, :name}) != verdict_key(VerdictProject, :update)
    end

    test "gives fields of an update covered by the same lines one key" do
      keys =
        for field <- [:summary, :title, :name],
            do: verdict_key(Hologram.PolicyTest.SharedFieldProject, {:update, field})

      assert [shared, shared, other] = keys
      assert shared != other
    end

    test "gives an operation a new key when its rules change" do
      open_key = operation_key_with_rules("allow :delete, when: open == true")

      assert operation_key_with_rules("allow :delete, when: open == false") != open_key
      assert operation_key_with_rules("allow :delete, when: open == true") == open_key
    end

    test "gives a field of an update a new key when a whole-row update rule changes" do
      limited_line = "allow :update, only: [:open], when: open == true"
      open_key = operation_key_with_rules(limited_line, {:update, :open})

      assert operation_key_with_rules(
               "#{limited_line}\nallow :update, when: open == false",
               {:update, :open}
             ) != open_key
    end

    # The two types declare the same label computed two ways, so the same rule over it means two
    # things - while over an attribute it means one.
    test "gives an operation reading a derived field a new key when the field's definition changes" do
      put_derived_definitions([LabelledMember, RelabelledMember])

      assert verdict_key(LabelledMember, :delete) != verdict_key(RelabelledMember, :delete)
      assert verdict_key(LabelledMember, :update) == verdict_key(RelabelledMember, :update)
    end

    # The key a verdict was told under is never read for what a changed set holds now.
    test "gives an operation over a derived set a new key when the set's definition changes" do
      put_derived_definitions([KeyedBoard])

      key = verdict_key(KeyedBoard, :delete)
      {:query, term} = Derived.definition(KeyedBoard, :top_cards)

      Derived.put_definitions(%{{KeyedBoard, :top_cards} => {:query, %{term | take: 3}}})

      assert verdict_key(KeyedBoard, :delete) != key
    end

    test "gives an operation over a derived set a new key when a field its definition reads changes" do
      put_derived_definitions([ScoredBoard, ScoredCard])

      key = verdict_key(ScoredBoard, :delete)

      Derived.put_definitions(%{{ScoredCard, :score} => {:value, 0}})

      assert verdict_key(ScoredBoard, :delete) != key
    end

    # The vault has no read rule, so the parcel's read rule delegating to it is answered by the
    # server's verdict, which a changed vault rule moves.
    test "gives an operation a new key when a rule its delegation asks changes" do
      compile_keyed_vault("allow :update, when: open == true")
      open_key = verdict_key(Hologram.PolicyTest.KeyedParcel, :read)

      compile_keyed_vault("allow :update, when: open == false")
      closed_key = verdict_key(Hologram.PolicyTest.KeyedParcel, :read)

      assert open_key != closed_key
    end
  end

  describe "verdict_operations/1" do
    defmodule VerdictProject do
      use Hologram.Entity

      attribute :name, :string

      relationship :labels, [Hologram.PolicyTest.VerdictLabel]
      relationship :members, [Hologram.PolicyTest.VerdictMember], inverse: project

      allow :read, when: any(member <- members, member.user_id == user_id())
      allow :update, when: name == "open" or all(member <- members, member.seat == "full")
      allow :delete, when: none(labels)
      allow :update, as: :archive, only: [:name], when: none(labels)

      allow :update,
        as: :close,
        only: [:name],
        when: any(member <- members, none(label <- member.project.labels, label.name == "x"))
    end

    defmodule VerdictMember do
      use Hologram.Entity

      attribute :seat, :string

      relationship :project, VerdictProject, optional: true
      relationship :user, Module14, optional: true

      allow :read
    end

    defmodule VerdictLabel do
      use Hologram.Entity

      attribute :name, :string

      allow :read
    end

    defmodule ServerOnlyReport do
      use Hologram.Entity

      attribute :reviewed, :boolean, server_only: true
      attribute :reviewed_on, :date, server_only: true, optional: true
      attribute :title, :string

      relationship :comments, [Hologram.PolicyTest.ServerOnlyComment], inverse: report

      allow :read, when: reviewed == true or title == "x"
    end

    defmodule ServerOnlyComment do
      use Hologram.Entity

      attribute :body, :string
      attribute :flagged, :boolean, server_only: true

      relationship :report, ServerOnlyReport, optional: true

      allow :read
    end

    defmodule FieldVerdictProject do
      use Hologram.Entity

      attribute :name, :string

      relationship :labels, [Hologram.PolicyTest.VerdictLabel]
      relationship :members, [Hologram.PolicyTest.VerdictMember]

      allow :update, when: none(labels)
      allow :update, only: [:name], when: any(member <- members, member.seat == "x")
    end

    # The read rule's any reads no none or all, so the browser answers it from the rows it holds.
    test "returns every operation whose rules hold a deciding item, keyed" do
      operations = [:archive, :close, :delete, :update, {:update, :name}]

      assert verdict_operations(VerdictProject) ==
               operations
               |> Enum.map(&{verdict_key(VerdictProject, &1), &1})
               |> Enum.sort()
    end

    test "returns a read rule's operation for a predicate on a server-only attribute" do
      assert verdict_operations(ServerOnlyReport) == [
               {verdict_key(ServerOnlyReport, :read), :read}
             ]
    end

    test "returns a read rule's operation for a role reference or a delegation" do
      assert verdict_operations(Policy.Readers.Module24) == [
               {verdict_key(Policy.Readers.Module24, :read), :read}
             ]

      assert verdict_operations(Policy.Readers.Module28) == [
               {verdict_key(Policy.Readers.Module28, :read), :read}
             ]
    end

    # The field's verdict would answer the whole-row rule too, which update's verdict answers.
    test "returns a field of an update only when its own lines hold a deciding item" do
      assert verdict_operations(FieldVerdictProject) == [
               {verdict_key(FieldVerdictProject, :update), :update}
             ]
    end

    test "returns nothing for a type with no deciding item" do
      assert verdict_operations(Module14) == []
    end

    # A workshop, a bench and a permit are read by the workshop's owner and members alone, so a
    # reader of a tool may not hold the ones its rules read: through a condition, a delegation, a
    # role held on the bench's workshop and an any over the permits. A create line counts only
    # under its name, since no verdict answers a check on a struct no row stores yet.
    test "returns every operation but create whose rules read a related row a reader may not hold" do
      operations = [:delete, :draft, :read, :update, {:update, :bench}, {:update, :label}]

      assert verdict_operations(Policy.Module49) ==
               operations
               |> Enum.map(&{verdict_key(Policy.Module49, &1), &1})
               |> Enum.sort()
    end

    # Control: every session reads every channel.
    test "returns nothing for rules reading only rows every session may read" do
      assert verdict_operations(Policy.Module39) == []
    end

    # Control: a crate is read through its workshop, and a box by the workshop's members, whom the
    # workshop's read rule admits, so every reader holds the workshop. The crate's delete reads the
    # workshop's site too, which every session reads. The box's delete reads only the workshop's
    # id, off the box itself.
    test "returns nothing for rules reading only rows every reader of the row may read" do
      assert verdict_operations(Policy.Module50) == []
      assert verdict_operations(Policy.Module51) == []
    end

    # A row read through its workshop by one rule but not by the other may be read by someone who
    # can't read the workshop.
    test "returns an operation reading a related row only some read rules admit readers of" do
      assert verdict_operations(Policy.Module53) ==
               [:read, :update]
               |> Enum.map(&{verdict_key(Policy.Module53, &1), &1})
               |> Enum.sort()
    end

    # The workshop admits its members and owners, not its editors.
    test "returns an operation reading a related row whose read rules don't admit the role read by" do
      assert verdict_operations(Policy.Module54) == [
               {verdict_key(Policy.Module54, :update), :update}
             ]
    end

    # Every reader holds the box, but not every reader of the box holds its workshop.
    test "returns an operation reading a related row a held row leads to that a reader may not hold" do
      assert verdict_operations(Policy.Module57) == [
               {verdict_key(Policy.Module57, :update), :update}
             ]
    end

    # The permit's read rule holds the role on the tool's workshop, read off the tool, which a
    # reader of the permit may not hold.
    test "returns a read rule's operation for a role reference through a row a reader may not hold" do
      assert verdict_operations(Policy.Module48) == [
               {verdict_key(Policy.Module48, :read), :read}
             ]
    end

    # Control: a role held one relationship away is looked up by the id the row itself holds.
    test "returns nothing for a role reference one relationship away" do
      assert verdict_operations(Policy.Module55) == []
    end

    # Control: no client is sent a bin.
    test "returns nothing for a type no session may read" do
      assert verdict_operations(Policy.Module52) == []
    end

    # Every field but the name is covered by the one line, so they share its key.
    test "returns one key for the fields of an update the same lines cover" do
      pairs = verdict_operations(Hologram.PolicyTest.SharedFieldProject)
      keys = Enum.map(pairs, fn {key, _operation} -> key end)

      assert {:update, :summary} in Enum.map(pairs, &elem(&1, 1))
      assert {:update, :title} in Enum.map(pairs, &elem(&1, 1))
      assert length(Enum.uniq(keys)) == 1
    end
  end

  describe "verdict_reads/2" do
    defmodule KeyedProject do
      use Hologram.Entity

      relationship :members, [Hologram.PolicyTest.KeyedMember], inverse: project

      allow :read
    end

    defmodule KeyedMember do
      use Hologram.Entity

      attribute :first, :string

      relationship :project, KeyedProject, optional: true

      derived :label, :string, fn first -> first <> "!" end

      allow :read
    end

    test "returns the types along a delegation's chain" do
      assert verdict_reads(Policy.Readers.Module28, {:via, {:read, [:shelf, :crate]}}) == [
               Policy.Readers.Module26,
               Policy.Readers.Module27
             ]
    end

    # The vault's close rule holds a role on the vault.
    test "returns the grant store for a delegation to a rule holding a role" do
      assert verdict_reads(Policy.Readers.Module28, {:via, {:close, [:vault]}}) == [
               RoleGrant,
               Policy.Readers.Module25
             ]
    end

    # A pending grant or revoke names the grant store.
    test "returns the types a role reference reads before its last relationship and the grant store" do
      item = {:to, {:rel, [:project, :team], [:member]}}

      assert verdict_reads(Policy.Readers.Module24, item) == [RoleGrant, Policy.Readers.Module23]
    end

    test "returns the rule's type and every type along the clause's sets and paths" do
      clause =
        {:any,
         {[:members],
          [{:none, {[:project, :labels], [{:name, :==, "x"}]}}, {[:user, :email], :==, "a"}]}}

      assert verdict_reads(Hologram.PolicyTest.VerdictProject, clause) ==
               Enum.sort([
                 Module14,
                 Hologram.PolicyTest.VerdictLabel,
                 Hologram.PolicyTest.VerdictMember,
                 Hologram.PolicyTest.VerdictProject
               ])
    end

    test "returns the types a derived field in the condition reads" do
      put_derived_definitions([Hologram.PolicyTest.KeyedMember])

      clause = {:none, {[:members], [{:label, :==, "x"}]}}

      assert verdict_reads(Hologram.PolicyTest.KeyedProject, clause) ==
               Enum.sort([Hologram.PolicyTest.KeyedMember, Hologram.PolicyTest.KeyedProject])
    end

    test "returns the types of a nested quantifier's set read on a row above" do
      clause =
        {:any, {[:members], [{:none, {{:outer, 1, [:labels]}, []}}]}}

      assert verdict_reads(Hologram.PolicyTest.VerdictProject, clause) ==
               Enum.sort([
                 Hologram.PolicyTest.VerdictLabel,
                 Hologram.PolicyTest.VerdictMember,
                 Hologram.PolicyTest.VerdictProject
               ])
    end

    test "returns the types a derived set's definition reads" do
      board = Hologram.PolicyTest.LockedBoard

      put_derived_definitions([board, Hologram.PolicyTest.LockedCard])

      clause = {:none, {[:busy_cards], [{:rank, :==, 1}]}}

      assert verdict_reads(board, clause) ==
               Enum.sort([board, Hologram.PolicyTest.LockedCard, Hologram.PolicyTest.LockedTag])
    end

    test "returns the types along a set its condition reads nothing on" do
      assert verdict_reads(Hologram.PolicyTest.VerdictProject, {:none, {[:labels], []}}) ==
               Enum.sort([Hologram.PolicyTest.VerdictLabel, Hologram.PolicyTest.VerdictProject])
    end

    # No client write can carry a server-only value, and a struct a pending write changed isn't the
    # stored row the verdict is about, so no unanswered write moves it.
    test "returns no type for a predicate reading only server-only attributes of the row" do
      report = Hologram.PolicyTest.ServerOnlyReport

      assert verdict_reads(report, {:reviewed, :==, true}) == []
      assert verdict_reads(report, {:reviewed_on, :!=, nil}) == []
    end

    # A struct a pending write changed isn't the stored row the verdict is about, so no unanswered
    # write to the row, or to another row of its type, moves it.
    test "returns no type for a predicate reading only attributes of the row" do
      report = Hologram.PolicyTest.ServerOnlyReport

      assert verdict_reads(report, {:title, :==, {:attribute, :reviewed}}) == []
    end

    # A quantifier reads its set even when its condition names only the row above.
    test "returns the types along a set whose condition names only the row's server-only attribute" do
      report = Hologram.PolicyTest.ServerOnlyReport
      clause = {:any, {[:comments], [{{:outer, 1, :reviewed}, :==, true}]}}

      assert verdict_reads(report, clause) ==
               Enum.sort([report, Hologram.PolicyTest.ServerOnlyComment])
    end

    test "returns the types along a path to a type nobody may read" do
      task = Hologram.PolicyTest.UnreadableReadTask

      assert verdict_reads(task, {[:project, :archived], :==, false}) == [
               Hologram.PolicyTest.UnreadableProject
             ]
    end

    test "returns the rule's own type for a path leading back to it" do
      task = Hologram.PolicyTest.UnreadableReadTask

      assert verdict_reads(task, {[:parent, :project, :archived], :==, false}) ==
               Enum.sort([task, Hologram.PolicyTest.UnreadableProject])
    end

    test "returns the types along a path to a server-only attribute, without the rule's own" do
      comment = Hologram.PolicyTest.ServerOnlyComment

      assert verdict_reads(comment, {[:report, :reviewed], :==, true}) ==
               [Hologram.PolicyTest.ServerOnlyReport]
    end
  end

  describe "verdict_related_reads/2" do
    # A delegation from the parcel to its crate, whose read rule delegates on to the vault through
    # its parcel's path, reads what both rules read.
    test "returns what the rules a delegation asks read, through their own delegations" do
      assert verdict_related_reads(Hologram.PolicyTest.RelayParcel, {:via, {:read, [:crate]}}) ==
               Enum.sort([
                 RoleGrant,
                 Hologram.PolicyTest.RelayCrate,
                 Hologram.PolicyTest.RelayVault
               ])
    end

    defmodule RelayVault do
      use Hologram.Entity

      role :member

      allow :delete, to: :member
    end

    defmodule RelayCrate do
      use Hologram.Entity

      relationship :vault, RelayVault, optional: true

      allow :read, via: {:delete, vault}
    end

    defmodule RelayParcel do
      use Hologram.Entity

      relationship :crate, RelayCrate, optional: true

      allow :read, via: crate
    end

    test "returns the types a role reference reads before its last relationship and the grant store" do
      item = {:to, {:rel, [:project, :team], [:member]}}

      assert verdict_related_reads(Policy.Readers.Module24, item) == [
               RoleGrant,
               Policy.Readers.Module23
             ]
    end

    test "returns the types the clause reaches through a relationship, leaving out the rule's own type" do
      assert verdict_related_reads(Hologram.PolicyTest.VerdictProject, {:none, {[:labels], []}}) ==
               [Hologram.PolicyTest.VerdictLabel]
    end

    test "returns the rule's own type when a relationship leads to a row of it" do
      clause = {:any, {[:members], [{:none, {[:project, :labels], [{:name, :==, "x"}]}}]}}

      assert verdict_related_reads(Hologram.PolicyTest.VerdictProject, clause) ==
               Enum.sort([
                 Hologram.PolicyTest.VerdictLabel,
                 Hologram.PolicyTest.VerdictMember,
                 Hologram.PolicyTest.VerdictProject
               ])
    end
  end

  # A deploy changes what a type declares while its name stays, so the type is defined again under
  # one name for each version of it.
  defp hash_of_project(body) do
    ignore_module_conflict? = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      Code.compile_string("""
      defmodule Hologram.PolicyTest.HashedProject do
        use Hologram.Entity

      #{body}
      end
      """)
    after
      Code.put_compiler_option(:ignore_module_conflict, ignore_module_conflict?)
    end

    put_derived_definitions([Hologram.PolicyTest.HashedProject])

    hash([Hologram.PolicyTest.HashedProject])
  end

  # Defines KeyedParcel's vault with the given rules and no read rule.
  defp compile_keyed_vault(rules) do
    ignore_module_conflict? = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      Code.compile_string("""
      defmodule Hologram.PolicyTest.KeyedVault do
        use Hologram.Entity

        attribute :open, :boolean, default: false

      #{rules}
      end
      """)
    after
      Code.put_compiler_option(:ignore_module_conflict, ignore_module_conflict?)
    end
  end

  # The key of the given operation of a type defined with the given rules, delete by default.
  defp operation_key_with_rules(rules, operation \\ :delete) do
    ignore_module_conflict? = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      Code.compile_string("""
      defmodule Hologram.PolicyTest.RekeyedTask do
        use Hologram.Entity

        attribute :open, :boolean, default: false

      #{rules}
      end
      """)
    after
      Code.put_compiler_option(:ignore_module_conflict, ignore_module_conflict?)
    end

    verdict_key(Hologram.PolicyTest.RekeyedTask, operation)
  end
end
