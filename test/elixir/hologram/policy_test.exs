defmodule Hologram.PolicyTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy,
    only: [
      build: 1,
      dead_entity_types: 1,
      deciding_quantifier?: 2,
      deciding_quantifiers: 1,
      delegation: 2,
      expand_global_role: 1,
      expand_global_role: 2,
      framework_operations: 0,
      grant_role_qualifying_roles: 1,
      grant_role_qualifying_roles: 2,
      held_chains: 2,
      locked_set_links: 1,
      operation_key: 1,
      operations: 1,
      read_roles_qualifying_role_modules: 1,
      read_roles_qualifying_roles: 1,
      related_chains: 1,
      related_chains: 2,
      revoke_role_qualifying_roles: 1,
      revoke_role_qualifying_roles: 2,
      validate_operation!: 2,
      verdict_key: 3,
      verdict_reads: 2,
      verdict_related_reads: 2
    ]

  alias Hologram.Auth.RoleGrant
  alias Hologram.Entity.Derived
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

        allow :archive, when: id == user_id()
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
        "invalid operation 123 used for allow in Hologram.PolicyTest.InvalidAllowPolicyFixture - an entity operation is an atom, or {:grant_role, role} / {:revoke_role, role} naming a declared role or a list of them"

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

      assert build(Policy.Module1) == %{
               :archive => [
                 %{predicates: [{:author_id, :==, {:actor}}], to: nil, via: nil}
               ],
               :delete => [
                 %{predicates: [], to: [{:rel, [:parent], [:admin]}], via: nil}
               ],
               :grant_role => [owner_rule, owner_rule],
               :publish => [
                 %{predicates: [], to: nil, via: {:publish, [:parent]}}
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

    test "keeps the operation a delegation names" do
      assert build(Policy.Module11) == %{
               create: [%{predicates: [], to: nil, via: {:update, [:parent]}}]
             }
    end

    test "follows a path in a condition, a delegation and a grant reference" do
      assert build(Policy.Module12) == %{
               archive: [%{predicates: [{[:link, :priority], :==, :high}], to: nil, via: nil}],
               delete: [
                 %{
                   predicates: [{:level, :<=, {:attribute, [:parent, :parent, :priority]}}],
                   to: nil,
                   via: nil
                 }
               ],
               publish: [%{predicates: [], to: nil, via: {:publish, [:parent, :parent]}}],
               read: [
                 %{predicates: [{[:parent, :parent, :public], :==, true}], to: nil, via: nil}
               ],
               triage: [
                 %{
                   predicates: [{[:parent, :parent, :created_at], :>=, ~U[2026-01-01 00:00:00Z]}],
                   to: nil,
                   via: nil
                 }
               ],
               update: [%{predicates: [], to: [{:rel, [:parent, :parent], [:viewer]}], via: nil}]
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

  describe "deciding_quantifier?/2" do
    test "holds for a none and an all" do
      project = Hologram.PolicyTest.VerdictProject

      assert deciding_quantifier?(project, {:none, {[:members], []}})
      assert deciding_quantifier?(project, {:all, {[:members], [{:seat, :==, "full"}]}})
    end

    test "holds for an any holding a none in an alternative of its condition" do
      inner = [{:or, [[{:seat, :==, "full"}], [{:none, {{:outer, 1, [:labels]}, []}}]]}]

      assert deciding_quantifier?(Hologram.PolicyTest.VerdictProject, {:any, {[:members], inner}})
    end

    # A bounded set computed over the rows a client holds can hold rows the server's doesn't.
    test "holds for an any over a derived set" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.LockedBoard,
               {:any, {[:top_cards], [{:rank, :==, 1}]}}
             )
    end

    test "holds for an any holding an any over a derived set" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.LockedTeam,
               {:any, {[:boards], [{:any, {[:top_cards], []}}]}}
             )
    end

    test "holds for an any over a derived set past a relationship to its owner" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.TopCardsRule,
               {:any, {[:board, :top_cards], []}}
             )
    end

    # The inner source is read on the board, one quantifier out, which holds the derived set.
    test "holds for an any holding an any over a derived set read on the row above" do
      clause = {:any, {[:cards], [{:any, {{:outer, 1, [:top_cards]}, []}}]}}

      assert deciding_quantifier?(Hologram.PolicyTest.LockedBoard, clause)
    end

    test "fails for an any holding an any over a stored set read on the row above" do
      clause = {:any, {[:cards], [{:any, {{:outer, 1, [:cards]}, []}}]}}

      refute deciding_quantifier?(Hologram.PolicyTest.LockedBoard, clause)
    end

    # A client can't compute the count.
    test "holds for an any whose condition reads a derived field counting a set" do
      assert deciding_quantifier?(
               Hologram.PolicyTest.LockedBoard,
               {:any, {[:cards], [{:tag_count, :<, 2}]}}
             )
    end

    test "fails for an any alone and for a predicate" do
      project = Hologram.PolicyTest.VerdictProject

      refute deciding_quantifier?(project, {:any, {[:members], [{:seat, :==, "full"}]}})
      refute deciding_quantifier?(project, {:seat, :==, "full"})
    end
  end

  describe "deciding_quantifiers/1" do
    defmodule VerdictProject do
      use Hologram.Entity

      attribute :name, :string

      relationship :labels, [Hologram.PolicyTest.VerdictLabel]
      relationship :members, [Hologram.PolicyTest.VerdictMember], inverse: project

      allow :read, when: any(member <- members, member.user_id == user_id())
      allow :update, when: name == "open" or all(member <- members, member.seat == "full")
      allow :delete, when: none(labels)
      allow :archive, when: none(labels)

      allow :close,
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

    # The read rule's any reads no none or all, so the browser answers it from the rows it holds -
    # the others are keyed by their operation and clause.
    test "returns the deciding quantifiers of every operation, keyed" do
      update_clause = {:all, {[:members], [{:seat, :==, "full"}]}}
      none_clause = {:none, {[:labels], []}}

      close_clause =
        {:any, {[:members], [{:none, {[:project, :labels], [{:name, :==, "x"}]}}]}}

      assert deciding_quantifiers(VerdictProject) ==
               Enum.sort([
                 {verdict_key(VerdictProject, :archive, none_clause), none_clause},
                 {verdict_key(VerdictProject, :close, close_clause), close_clause},
                 {verdict_key(VerdictProject, :delete, none_clause), none_clause},
                 {verdict_key(VerdictProject, :update, update_clause), update_clause}
               ])
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

      allow :archive, when: any(seat <- seats, none(tag <- seat.tags, tag.name == "x"))
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

  describe "operations/1" do
    test "returns the framework's operations and the ones the allow lines name, sorted" do
      assert operations(Policy.Module1) == [
               :archive,
               :create,
               :delete,
               :grant_role,
               :publish,
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

    test "includes an operation named by a line taken from a policy module" do
      defmodule TakenOperationPolicyFixture do
        use Hologram.Policy

        allow :publish, when: public == true
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
      allow :archive, when: any(member <- first_members, member.seat == "full")
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
    test "passes every framework operation on an entity type declaring nothing" do
      Enum.each(framework_operations(), fn operation ->
        assert validate_operation!(Module1, operation) == :ok
      end)
    end

    test "passes an operation an allow line on the entity type names" do
      assert validate_operation!(Policy.Module1, :archive) == :ok
    end

    test "passes a role tuple naming a role the entity type declares" do
      assert validate_operation!(Policy.Module1, {:grant_role, :editor}) == :ok
      assert validate_operation!(Policy.Module1, {:revoke_role, :viewer}) == :ok
    end

    test "raises on an operation no allow line on the entity type names" do
      expected_msg =
        "unknown operation :pin for Hologram.Test.Fixtures.Policy.Module1 - its allow lines declare :archive and :publish, and the framework's own operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update"

      assert_error ArgumentError, expected_msg, fn ->
        validate_operation!(Policy.Module1, :pin)
      end
    end

    test "raises on an operation for an entity type whose allow lines name none of their own" do
      expected_msg =
        "unknown operation :archive for Hologram.Test.Fixtures.Entity.Module1 - its allow lines declare no operation of their own, and the framework's own operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update"

      assert_error ArgumentError, expected_msg, fn ->
        validate_operation!(Module1, :archive)
      end
    end

    test "names a single declared operation without a conjunction" do
      expected_msg =
        "unknown operation :publish for Hologram.Test.Fixtures.Policy.Module4 - its allow lines declare :archive, and the framework's own operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update"

      assert_error ArgumentError, expected_msg, fn ->
        validate_operation!(Policy.Module4, :publish)
      end
    end

    test "raises on a role tuple naming a role the entity type does not declare" do
      expected_msg =
        "unknown role :editr in {:grant_role, :editr} for Hologram.Test.Fixtures.Policy.Module1 - declared roles are: :editor, :maintainer, :owner, :viewer"

      assert_error ArgumentError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:grant_role, :editr})
      end
    end

    test "raises on a role tuple for an entity type declaring no role" do
      expected_msg =
        "unknown role :editor in {:revoke_role, :editor} for Hologram.Test.Fixtures.Entity.Module1 - it declares no role"

      assert_error ArgumentError, expected_msg, fn ->
        validate_operation!(Module1, {:revoke_role, :editor})
      end
    end

    test "raises on a tuple whose name is not a grant lifecycle operation" do
      expected_msg =
        "unknown operation {:publish, :editor} for Hologram.Test.Fixtures.Policy.Module1 - the operation tuples are {:grant_role, role} and {:revoke_role, role}"

      assert_error ArgumentError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:publish, :editor})
      end
    end

    test "raises on a tuple that is not a pair" do
      expected_msg =
        "unknown operation {:grant_role, :editor, :extra} for Hologram.Test.Fixtures.Policy.Module1 - the operation tuples are {:grant_role, role} and {:revoke_role, role}"

      assert_error ArgumentError, expected_msg, fn ->
        validate_operation!(Policy.Module1, {:grant_role, :editor, :extra})
      end
    end

    test "raises on an operation that is neither an atom nor a tuple" do
      expected_msg =
        ~s(unknown operation "read" for Hologram.Test.Fixtures.Policy.Module1 - an entity operation is an atom, or {:grant_role, role} / {:revoke_role, role})

      assert_error ArgumentError, expected_msg, fn ->
        validate_operation!(Policy.Module1, wrap_term("read"))
      end
    end
  end

  describe "verdict_key/3" do
    defmodule KeyedProject do
      use Hologram.Entity

      attribute :title, :string

      relationship :members, [Hologram.PolicyTest.KeyedMember], inverse: project

      allow :read
    end

    defmodule KeyedMember do
      use Hologram.Entity

      attribute :first, :string
      attribute :seat, :string

      relationship :project, KeyedProject, optional: true

      derived :label, :string, fn first -> first <> "!" end

      allow :read
    end

    defmodule RekeyedMember do
      use Hologram.Entity

      attribute :first, :string

      derived :label, :string, fn first -> first <> "?" end

      allow :read
    end

    defmodule KeyedBoard do
      use Hologram.Entity

      relationship :cards, [Hologram.PolicyTest.KeyedCard]

      derived :top_cards, [Hologram.PolicyTest.KeyedCard], fn cards -> take(cards, 2) end
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
    end

    defmodule ScoredCard do
      use Hologram.Entity

      attribute :rank, :integer

      derived :score, :integer, fn rank -> rank end
    end

    # Verdicts are stored with the rows a client holds, so the key a clause gets is pinned - a
    # change to how keys are made would leave every stored verdict unread.
    test "keys a clause by its operation and a digest of it" do
      assert verdict_key(KeyedProject, :delete, {:none, {[:members], []}}) ==
               "delete:bb12cc9173b5a038"
    end

    test "gives a changed clause a new key and another operation another one" do
      key = verdict_key(KeyedProject, :delete, {:none, {[:members], []}})

      assert verdict_key(KeyedProject, :delete, {:all, {[:members], [{:seat, :==, "x"}]}}) != key
      assert verdict_key(KeyedProject, :archive, {:none, {[:members], []}}) != key
    end

    # The two types declare the same label computed two ways, so the same clause over it means two
    # things - while over an attribute it means one.
    test "gives a clause reading a derived field a new key when the field's definition changes" do
      put_derived_definitions([KeyedMember, RekeyedMember])

      assert verdict_key(KeyedMember, :delete, {:label, :==, "x"}) !=
               verdict_key(RekeyedMember, :delete, {:label, :==, "x"})

      assert verdict_key(KeyedMember, :delete, {:first, :==, "x"}) ==
               verdict_key(RekeyedMember, :delete, {:first, :==, "x"})
    end

    # The key a verdict was told under is never read for what a changed set holds now.
    test "gives a clause over a derived set a new key when the set's definition changes" do
      put_derived_definitions([KeyedBoard])

      clause = {:any, {[:top_cards], [{:rank, :==, 1}]}}
      key = verdict_key(KeyedBoard, :delete, clause)
      {:query, term} = Derived.definition(KeyedBoard, :top_cards)

      Derived.put_definitions(%{{KeyedBoard, :top_cards} => {:query, %{term | take: 3}}})

      assert verdict_key(KeyedBoard, :delete, clause) != key
    end

    test "gives a clause over a derived set a new key when a field its definition reads changes" do
      put_derived_definitions([ScoredBoard, ScoredCard])

      clause = {:any, {[:top_cards], [{:rank, :==, 1}]}}
      key = verdict_key(ScoredBoard, :delete, clause)

      Derived.put_definitions(%{{ScoredCard, :score} => {:value, 0}})

      assert verdict_key(ScoredBoard, :delete, clause) != key
    end

    test "keys a per-role operation the way the client spells it" do
      assert "grant_role:editor:" <> _digest =
               verdict_key(KeyedProject, {:grant_role, :editor}, {:none, {[:members], []}})
    end
  end

  describe "verdict_reads/2" do
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
  end

  describe "verdict_related_reads/2" do
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
end
