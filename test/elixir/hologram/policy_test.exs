defmodule Hologram.PolicyTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2

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
        "multiple user entity designations in the data model: Hologram.PolicyTest.InlinePolicyFixture27, Hologram.PolicyTest.InlinePolicyFixture28 - exactly one entity type can be designated with use Hologram.Entity, user: true"

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
        "Hologram.PolicyTest.InlinePolicyFixture29 declares roles or policy grant references, but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

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
        "Hologram.PolicyTest.InlinePolicyFixture30 declares roles or policy grant references, but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

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
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture8 - user_id() requires a uuid attribute - attribute :title in Hologram.PolicyTest.InlinePolicyFixture8 has type :string"

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
        "unknown role :publisher in the to option of allow :update in Hologram.PolicyTest.InlinePolicyFixture11 - declared roles are: :editor, :owner"

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
        "invalid to option {Hologram.Reflection, :editor} for allow :update in Hologram.PolicyTest.InlinePolicyFixture15 - Hologram.Reflection is not an entity type module"

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
        "unknown role :publisher in the to option of allow :update in Hologram.PolicyTest.InlinePolicyFixture16 - declared roles of Hologram.Test.Fixtures.Entity.Module13 are: :editor, :owner"

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
        "unknown relationship :project in the to option of allow :update in Hologram.PolicyTest.InlinePolicyFixture18 - declared relationships are: :parent"

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
        "invalid to option {:children, :editor} for allow :update in Hologram.PolicyTest.InlinePolicyFixture19 - relationship :children is to-many, but a role reference requires a to-one relationship"

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
        "unknown role :publisher in the to option of allow :update in Hologram.PolicyTest.InlinePolicyFixture20 - declared roles of Hologram.Test.Fixtures.Entity.Module13 are: :editor, :owner"

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
        "invalid to option \"owner\" for allow :update in Hologram.PolicyTest.InlinePolicyFixture12 - the to option must be a role name, a {module, role} or {relationship, role} tuple, or a non-empty list of them"

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
        "unknown relationship :project in the via option of allow :read in Hologram.PolicyTest.InlinePolicyFixture22 - declared relationships are: :parent"

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
        "invalid via option :children for allow :read in Hologram.PolicyTest.InlinePolicyFixture23 - relationship :children is to-many, but delegation requires a to-one relationship"

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
        "invalid via option \"parent\" for allow :read in Hologram.PolicyTest.InlinePolicyFixture24 - the via option must be a relationship name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture24])
      end
    end

    test "rejects a delegation cycle spanning two entity types" do
      defmodule InlinePolicyFixture25 do
        use Hologram.Entity

        relationship :peer, Hologram.PolicyTest.InlinePolicyFixture26, optional: true

        allow :read, via: :peer
      end

      defmodule InlinePolicyFixture26 do
        use Hologram.Entity

        relationship :peer, Hologram.PolicyTest.InlinePolicyFixture25, optional: true

        allow :read, via: :peer
      end

      expected_msg =
        normalize_newlines("""
        cyclic policy delegation for allow :read - a via chain can't return to the entity type it starts from:
          * Hologram.PolicyTest.InlinePolicyFixture25 (via :peer) -> Hologram.PolicyTest.InlinePolicyFixture26 (via :peer) -> Hologram.PolicyTest.InlinePolicyFixture25\
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
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture3 - unknown attribute :published in Hologram.PolicyTest.InlinePolicyFixture3 - known attributes: :created_at, :id, :title, :updated_at"

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
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture4 - :parent is a relationship in Hologram.PolicyTest.InlinePolicyFixture4 - only attributes can be filtered - filter its reference via :parent_id"

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
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture5 - unknown operator :like in the filter predicate for attribute :title - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in"

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
        "invalid predicate for allow :read in Hologram.PolicyTest.InlinePolicyFixture6 - operator :>= requires a numeric or temporal attribute - attribute :parent_id in Hologram.PolicyTest.InlinePolicyFixture6 has type :uuid"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture6])
      end
    end
  end
end
