defmodule Hologram.Policy.CompilerTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy.Compiler

  alias Hologram.Auth.RoleGrant
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Policy
  alias Hologram.Test.Fixtures.Role

  describe "build/1" do
    test "returns empty map for entity type without policy declarations" do
      assert build(Module1) == %{}
    end

    test "builds rules per operation, keeping declaration order" do
      assert build(Policy.Module1) == %{
               archive: [
                 %{predicates: [{:author_id, :==, {:actor}}], to: nil, via: nil}
               ],
               delete: [
                 %{predicates: [], to: [{:rel, :parent, [:admin]}], via: nil}
               ],
               manage_roles: [
                 %{predicates: [], to: [{:own, [:owner]}], via: nil}
               ],
               publish: [
                 %{predicates: [], to: nil, via: :parent}
               ],
               read: [
                 %{predicates: [{:public, :==, true}], to: nil, via: nil},
                 %{
                   predicates: [],
                   to: [{:own, [:viewer]}, {:type, Policy.Module2, [:admin]}],
                   via: nil
                 }
               ],
               update: [
                 %{predicates: [{:priority, :>=, 3}], to: [{:own, [:editor, :owner]}], via: nil}
               ]
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
                   to: [{:resource, Policy.Module2, [:member]}],
                   via: nil
                 }
               ]
             }
    end
  end

  describe "cross_app_global_roles/1" do
    defp register_fixture_app(app, modules) do
      :ok = :application.load({:application, app, [modules: modules]})
      on_exit(fn -> :application.unload(app) end)

      :ok
    end

    test "pairs a global role declared in several OTP apps with those apps" do
      defmodule CrossAppGlobalRoleFixture1 do
        use Hologram.Entity

        role :admin, scope: :global
      end

      register_fixture_app(:hologram_cross_app_global_role_fixture_app_1, [
        CrossAppGlobalRoleFixture1
      ])

      assert cross_app_global_roles([Policy.Module2, CrossAppGlobalRoleFixture1]) == [
               {:admin, [:hologram, :hologram_cross_app_global_role_fixture_app_1]}
             ]
    end

    test "returns empty list for a global role declared within a single OTP app" do
      assert cross_app_global_roles([Policy.Module1, Policy.Module2]) == []
    end

    test "returns empty list for a resource-scoped role name shared across OTP apps" do
      defmodule CrossAppGlobalRoleFixture2 do
        use Hologram.Entity

        role :viewer
      end

      register_fixture_app(:hologram_cross_app_global_role_fixture_app_2, [
        CrossAppGlobalRoleFixture2
      ])

      assert cross_app_global_roles([Policy.Module1, CrossAppGlobalRoleFixture2]) == []
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

  describe "global_role_names/0" do
    test "collects the roles declared with global scope across the data model" do
      assert global_role_names() == [:admin]
    end
  end

  describe "manage_roles_qualifying_roles/1" do
    test "returns the expanded own roles of the manage_roles rules" do
      assert manage_roles_qualifying_roles(Policy.Module1) == [:owner]
    end

    test "returns empty list when the entity type declares no manage_roles rule" do
      assert manage_roles_qualifying_roles(Policy.Module2) == []
    end
  end

  describe "read_grants_roles/1" do
    test "returns the expanded own roles of the read_grants rules" do
      assert read_grants_roles(Policy.Module2) == [:member]
    end

    test "defaults to the roles qualifying to manage grants" do
      assert read_grants_roles(Policy.Module1) == [:owner]
    end
  end

  describe "validate_model!/1" do
    test "returns :ok for empty model" do
      assert validate_model!([]) == :ok
    end

    test "returns :ok for entity types without policy declarations" do
      assert validate_model!([Module1, Module2]) == :ok
    end

    test "returns :ok for every declared predicate value kind" do
      defmodule InlinePolicyFixture1 do
        use Hologram.Entity

        attribute :count, :integer
        attribute :status, :enum, values: [:done, :todo]
        attribute :title, :string

        allow :read, status: :done
        allow :publish, count: {:>=, 3}
        allow :triage, status: [:done, :todo]
        allow :archive, count: 1..10
        allow :unlink, title: {:!=, nil}
      end

      assert validate_model!([InlinePolicyFixture1]) == :ok
    end

    test "returns :ok for a predicate on a to-one reference field" do
      assert validate_model!([Module13, Module14]) == :ok
    end

    test "returns :ok for bare allow lines" do
      defmodule InlinePolicyFixture2 do
        use Hologram.Entity

        relationship :parent, Module1

        role :owner

        allow :read
        allow :update, to: :owner
        allow :publish, via: :parent
      end

      assert validate_model!([Module14, InlinePolicyFixture2]) == :ok
    end

    test "returns :ok for a to option naming a declared role" do
      defmodule InlinePolicyFixture9 do
        use Hologram.Entity

        role :owner

        allow :update, to: :owner
      end

      assert validate_model!([Module14, InlinePolicyFixture9]) == :ok
    end

    test "returns :ok for a to option listing declared roles" do
      defmodule InlinePolicyFixture10 do
        use Hologram.Entity

        role :editor
        role :owner

        allow :update, to: [:editor, :owner]
      end

      assert validate_model!([Module14, InlinePolicyFixture10]) == :ok
    end

    test "returns :ok for a to option referencing a role of another entity type" do
      defmodule InlinePolicyFixture13 do
        use Hologram.Entity

        allow :update, to: {Module13, :editor}
      end

      assert validate_model!([Module14, InlinePolicyFixture13]) == :ok
    end

    test "returns :ok for a to option mixing role names and namespaced references" do
      defmodule InlinePolicyFixture14 do
        use Hologram.Entity

        role :owner

        allow :update, to: [:owner, {Module13, :editor}]
      end

      assert validate_model!([Module14, InlinePolicyFixture14]) == :ok
    end

    test "returns :ok for a to option referencing a role on a to-one relationship target" do
      defmodule InlinePolicyFixture17 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :update, to: {:parent, :editor}
      end

      assert validate_model!([Module14, InlinePolicyFixture17]) == :ok
    end

    test "returns :ok for a via option delegating to a to-one relationship" do
      defmodule InlinePolicyFixture21 do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        relationship :parent, Module13

        allow :read, via: :parent, public: true
      end

      assert validate_model!([InlinePolicyFixture21]) == :ok
    end

    test "returns :ok for actor leaves on uuid-carrying names" do
      defmodule InlinePolicyFixture7 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, id: user_id()
        allow :update, parent_id: {:!=, user_id()}
      end

      assert validate_model!([InlinePolicyFixture7]) == :ok
    end

    test "rejects multiple user entity designations" do
      defmodule InlinePolicyFixture27 do
        use Hologram.Entity, user: true
      end

      defmodule InlinePolicyFixture28 do
        use Hologram.Entity, user: true
      end

      expected_msg =
        "multiple user entity designations in the data model: Hologram.Policy.CompilerTest.InlinePolicyFixture27, Hologram.Policy.CompilerTest.InlinePolicyFixture28 - exactly one entity type can be designated with use Hologram.Entity, user: true"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture28, InlinePolicyFixture27])
      end
    end

    test "rejects role declarations without a user entity designation" do
      defmodule InlinePolicyFixture29 do
        use Hologram.Entity

        role :owner
      end

      expected_msg =
        "Hologram.Policy.CompilerTest.InlinePolicyFixture29 declares roles or policy grant references, but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture29])
      end
    end

    test "rejects a to option without a user entity designation" do
      defmodule InlinePolicyFixture30 do
        use Hologram.Entity

        allow :update, to: {Module13, :editor}
      end

      expected_msg =
        "Hologram.Policy.CompilerTest.InlinePolicyFixture30 declares roles or policy grant references, but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture30])
      end
    end

    test "rejects an actor leaf on a non-uuid attribute" do
      defmodule InlinePolicyFixture8 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, title: user_id()
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.CompilerTest.InlinePolicyFixture8 - user_id() requires a uuid attribute - attribute :title in Hologram.Policy.CompilerTest.InlinePolicyFixture8 has type :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture8])
      end
    end

    test "rejects a to option naming an undeclared role" do
      defmodule InlinePolicyFixture11 do
        use Hologram.Entity

        role :editor
        role :owner

        allow :update, to: [:editor, :publisher]
      end

      expected_msg =
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.CompilerTest.InlinePolicyFixture11 - declared roles are: :editor, :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture11])
      end
    end

    test "rejects a to option referencing a non-entity module" do
      defmodule InlinePolicyFixture15 do
        use Hologram.Entity

        allow :update, to: {Hologram.Reflection, :editor}
      end

      expected_msg =
        "invalid to option {Hologram.Reflection, :editor} for allow :update in Hologram.Policy.CompilerTest.InlinePolicyFixture15 - Hologram.Reflection is not an entity type module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture15])
      end
    end

    test "rejects a to option referencing an undeclared role of another entity type" do
      defmodule InlinePolicyFixture16 do
        use Hologram.Entity

        allow :update, to: {Module13, :publisher}
      end

      expected_msg =
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.CompilerTest.InlinePolicyFixture16 - declared roles of Hologram.Test.Fixtures.Entity.Module13 are: :editor, :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture16])
      end
    end

    test "rejects a to option naming an unknown relationship" do
      defmodule InlinePolicyFixture18 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :update, to: {:project, :editor}
      end

      expected_msg =
        "unknown relationship :project in the to option of allow :update in Hologram.Policy.CompilerTest.InlinePolicyFixture18 - declared relationships are: :parent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture18])
      end
    end

    test "rejects a to option referencing a role on a to-many relationship" do
      defmodule InlinePolicyFixture19 do
        use Hologram.Entity

        relationship :children, [Module13]

        allow :update, to: {:children, :editor}
      end

      expected_msg =
        "invalid to option {:children, :editor} for allow :update in Hologram.Policy.CompilerTest.InlinePolicyFixture19 - relationship :children is to-many, but a role reference requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture19])
      end
    end

    test "rejects a to option referencing an undeclared role on a relationship target" do
      defmodule InlinePolicyFixture20 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :update, to: {:parent, :publisher}
      end

      expected_msg =
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.CompilerTest.InlinePolicyFixture20 - declared roles of Hologram.Test.Fixtures.Entity.Module13 are: :editor, :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture20])
      end
    end

    test "rejects a to option that is neither a role reference nor a list of them" do
      defmodule InlinePolicyFixture12 do
        use Hologram.Entity

        role :owner

        allow :update, to: "owner"
      end

      expected_msg =
        "invalid to option \"owner\" for allow :update in Hologram.Policy.CompilerTest.InlinePolicyFixture12 - the to option must be a role name, a {module, role} or {relationship, role} tuple, or a non-empty list of them"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture12])
      end
    end

    test "rejects a via option naming an unknown relationship" do
      defmodule InlinePolicyFixture22 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :read, via: :project
      end

      expected_msg =
        "unknown relationship :project in the via option of allow :read in Hologram.Policy.CompilerTest.InlinePolicyFixture22 - declared relationships are: :parent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture22])
      end
    end

    test "rejects a via option naming a to-many relationship" do
      defmodule InlinePolicyFixture23 do
        use Hologram.Entity

        relationship :children, [Module13]

        allow :read, via: :children
      end

      expected_msg =
        "invalid via option :children for allow :read in Hologram.Policy.CompilerTest.InlinePolicyFixture23 - relationship :children is to-many, but delegation requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture23])
      end
    end

    test "rejects a via option that is not a relationship name" do
      defmodule InlinePolicyFixture24 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :read, via: "parent"
      end

      expected_msg =
        "invalid via option \"parent\" for allow :read in Hologram.Policy.CompilerTest.InlinePolicyFixture24 - the via option must be a relationship name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture24])
      end
    end

    test "rejects a delegation cycle spanning two entity types" do
      defmodule InlinePolicyFixture25 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.CompilerTest.InlinePolicyFixture26, optional: true

        allow :read, via: :peer
      end

      defmodule InlinePolicyFixture26 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.CompilerTest.InlinePolicyFixture25, optional: true

        allow :read, via: :peer
      end

      expected_msg =
        normalize_newlines("""
        cyclic policy delegation for allow :read - a via chain can't return to the entity type it starts from:
          * Hologram.Policy.CompilerTest.InlinePolicyFixture25 (via :peer) -> Hologram.Policy.CompilerTest.InlinePolicyFixture26 (via :peer) -> Hologram.Policy.CompilerTest.InlinePolicyFixture25\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture25, InlinePolicyFixture26])
      end
    end

    test "rejects a predicate naming an unknown attribute" do
      defmodule InlinePolicyFixture3 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, published: true
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.CompilerTest.InlinePolicyFixture3 - unknown attribute :published in Hologram.Policy.CompilerTest.InlinePolicyFixture3 - known attributes: :created_at, :id, :title, :updated_at"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture3])
      end
    end

    test "rejects a predicate naming a relationship" do
      defmodule InlinePolicyFixture4 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, parent: nil
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.CompilerTest.InlinePolicyFixture4 - :parent is a relationship in Hologram.Policy.CompilerTest.InlinePolicyFixture4 - only attributes can be filtered - filter its reference via :parent_id"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture4])
      end
    end

    test "rejects a predicate using an unknown operator" do
      defmodule InlinePolicyFixture5 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, title: {:like, "text_1"}
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.CompilerTest.InlinePolicyFixture5 - unknown operator :like in the filter predicate for attribute :title - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture5])
      end
    end

    test "rejects an ordering comparison on a to-one reference field" do
      defmodule InlinePolicyFixture6 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, parent_id: {:>=, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"}
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.CompilerTest.InlinePolicyFixture6 - operator :>= requires a numeric or temporal attribute - attribute :parent_id in Hologram.Policy.CompilerTest.InlinePolicyFixture6 has type :uuid"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture6])
      end
    end
  end

  describe "validate_model!/1 with global role references" do
    test "returns :ok for a declared role module reference" do
      defmodule ValidGlobalReferenceFixture do
        use Hologram.Entity

        allow :read, to: Hologram.Test.Fixtures.Role.Module1
      end

      assert validate_model!([Module14, ValidGlobalReferenceFixture]) == :ok
    end

    test "rejects a to option naming a module that is not a role" do
      defmodule InvalidGlobalReferenceFixture do
        use Hologram.Entity

        allow :read, to: Hologram.Test.Fixtures.Entity.Module1
      end

      expected_msg =
        "invalid to option Hologram.Test.Fixtures.Entity.Module1 for allow :read in Hologram.Policy.CompilerTest.InvalidGlobalReferenceFixture - Hologram.Test.Fixtures.Entity.Module1 is not a role module (define it with use Hologram.Role)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InvalidGlobalReferenceFixture])
      end
    end
  end

  describe "validate_role_modules!/1" do
    test "returns :ok for empty model" do
      assert validate_role_modules!([]) == :ok
    end

    test "returns :ok for roles extending declared roles" do
      assert validate_role_modules!([Role.Module1, Role.Module2]) == :ok
    end

    test "returns :ok for a role extending several roles" do
      defmodule MultiExtendsRoleFixture do
        use Hologram.Role, extends: [Role.Module1, Role.Module2]
      end

      assert validate_role_modules!([MultiExtendsRoleFixture]) == :ok
    end

    test "rejects an extends target that is not a role module" do
      defmodule InvalidTargetRoleFixture do
        use Hologram.Role, extends: Module1
      end

      expected_msg =
        "invalid extends target Hologram.Test.Fixtures.Entity.Module1 in use Hologram.Role for Hologram.Policy.CompilerTest.InvalidTargetRoleFixture - extends targets must be modules defined with use Hologram.Role"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_role_modules!([InvalidTargetRoleFixture])
      end
    end

    test "rejects an extension cycle" do
      defmodule CyclicRoleFixture1 do
        use Hologram.Role, extends: Hologram.Policy.CompilerTest.CyclicRoleFixture2
      end

      defmodule CyclicRoleFixture2 do
        use Hologram.Role, extends: Hologram.Policy.CompilerTest.CyclicRoleFixture1
      end

      expected_msg =
        normalize_newlines("""
        cyclic role extension - an extends chain can't return to the role it starts from:
          * Hologram.Policy.CompilerTest.CyclicRoleFixture1 -> Hologram.Policy.CompilerTest.CyclicRoleFixture2 -> Hologram.Policy.CompilerTest.CyclicRoleFixture1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_role_modules!([CyclicRoleFixture1, CyclicRoleFixture2])
      end
    end

    test "rejects a role module name too long to store as a grant value" do
      defmodule ThisIsAVeryLongRoleModuleNameUsedToExceedThePostgresEnumLabelLimit do
        use Hologram.Role
      end

      expected_msg =
        "role module name Hologram.Policy.CompilerTest.ThisIsAVeryLongRoleModuleNameUsedToExceedThePostgresEnumLabelLimit is too long to store as a grant value (95 bytes, limit 63) - shorten the module name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_role_modules!([
          ThisIsAVeryLongRoleModuleNameUsedToExceedThePostgresEnumLabelLimit
        ])
      end
    end
  end
end
