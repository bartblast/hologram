defmodule Hologram.Policy.ValidatorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy.Validator

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Role

  describe "validate_model!/2" do
    test "returns :ok for empty model" do
      assert validate_model!([], []) == :ok
    end

    test "returns :ok for entity types without policy declarations" do
      assert validate_model!([Module1, Module2], []) == :ok
    end

    test "returns :ok for every declared predicate value kind" do
      defmodule InlinePolicyFixture1 do
        use Hologram.Entity

        attribute :count, :integer
        attribute :status, :enum, values: [:done, :todo]
        attribute :title, :string

        allow :read, when: status == :done
        allow :update, as: :publish, when: count >= 3
        allow :update, as: :triage, when: status in [:done, :todo]
        allow :update, as: :archive, when: count in 1..10
        allow :update, as: :unlink, when: title != nil
      end

      assert validate_model!([InlinePolicyFixture1], []) == :ok
    end

    test "returns :ok for a predicate on a to-one reference field" do
      assert validate_model!([Module13, Module14], []) == :ok
    end

    test "returns :ok for bare allow lines" do
      defmodule InlinePolicyFixture2 do
        use Hologram.Entity

        relationship :parent, Module1

        role :owner

        allow :read
        allow :update, to: :owner
        allow :read, via: parent
      end

      assert validate_model!([Module14, InlinePolicyFixture2], []) == :ok
    end

    test "returns :ok for a to option naming a declared role" do
      defmodule InlinePolicyFixture9 do
        use Hologram.Entity

        role :owner

        allow :update, to: :owner
      end

      assert validate_model!([Module14, InlinePolicyFixture9], []) == :ok
    end

    test "returns :ok for a to option listing declared roles" do
      defmodule InlinePolicyFixture10 do
        use Hologram.Entity

        role :editor
        role :owner

        allow :update, to: [:editor, :owner]
      end

      assert validate_model!([Module14, InlinePolicyFixture10], []) == :ok
    end

    test "returns :ok for a to option referencing a role of another entity type" do
      defmodule InlinePolicyFixture13 do
        use Hologram.Entity

        allow :update, to: {:editor, Module13}
      end

      assert validate_model!([Module14, InlinePolicyFixture13], []) == :ok
    end

    test "returns :ok for a to option mixing role names and namespaced references" do
      defmodule InlinePolicyFixture14 do
        use Hologram.Entity

        role :owner

        allow :update, to: [:owner, {:editor, Module13}]
      end

      assert validate_model!([Module14, InlinePolicyFixture14], []) == :ok
    end

    test "returns :ok for a to option referencing a role on a to-one relationship target" do
      defmodule InlinePolicyFixture17 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :update, to: {:editor, parent}
      end

      assert validate_model!([Module14, InlinePolicyFixture17], []) == :ok
    end

    test "returns :ok for a to option referencing a role on the row a path ends at" do
      defmodule InlinePolicyFixture54 do
        use Hologram.Entity

        relationship :item, Hologram.Test.Fixtures.Entity.Module25

        allow :update, to: {:editor, item.h}
      end

      assert validate_model!([Module14, InlinePolicyFixture54], []) == :ok
    end

    test "returns :ok for a via option delegating to a to-one relationship" do
      defmodule InlinePolicyFixture21 do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        relationship :parent, Module13

        allow :read, via: parent, when: public == true
      end

      assert validate_model!([InlinePolicyFixture21], []) == :ok
    end

    test "returns :ok for a via option naming its operation" do
      defmodule InlinePolicyFixture40 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :delete, via: {:update, parent}
      end

      assert validate_model!([InlinePolicyFixture40], []) == :ok
    end

    test "returns :ok for a via option naming a framework operation the related entity type declares no rule for" do
      defmodule InlinePolicyFixture47 do
        use Hologram.Entity

        relationship :parent, Hologram.Test.Fixtures.Entity.Module25

        allow :create, via: {:update, parent}
      end

      assert validate_model!([InlinePolicyFixture47], []) == :ok
    end

    # A read rule may read through a type nobody may read: the browser checks it only on rows as
    # they were sent, and the server's verdict on each answers what it reads there.
    test "returns :ok for a read rule reading through a type nobody may read" do
      defmodule InlinePolicyFixture66 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, via: parent
      end

      assert validate_model!([InlinePolicyFixture66], []) == :ok
    end

    test "returns :ok for a via option following a path, alone or naming its operation" do
      defmodule InlinePolicyFixture52 do
        use Hologram.Entity

        relationship :item, Hologram.Test.Fixtures.Entity.Module25

        allow :read, via: item.h
        allow :delete, via: {:read, item.h}
      end

      assert validate_model!([InlinePolicyFixture52], []) == :ok
    end

    # Each create asks the other type's update, and neither update delegates, so no chain returns
    # to where it started.
    test "returns :ok for delegations that return to an entity type under another operation" do
      defmodule InlinePolicyFixture41 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.InlinePolicyFixture42, optional: true

        allow :create, via: {:update, peer}
        allow :read
      end

      defmodule InlinePolicyFixture42 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.InlinePolicyFixture41, optional: true

        allow :create, via: {:update, peer}
        allow :read
      end

      assert validate_model!([InlinePolicyFixture41, InlinePolicyFixture42], []) == :ok
    end

    test "returns :ok for actor leaves on uuid-carrying names" do
      defmodule InlinePolicyFixture7 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, when: id == user_id()
        allow :update, when: parent_id != user_id()
      end

      assert validate_model!([Module14, InlinePolicyFixture7], []) == :ok
    end

    test "returns :ok for a condition comparing two attributes" do
      defmodule InlinePolicyFixture37 do
        use Hologram.Entity

        attribute :capacity, :integer
        attribute :guests, :integer

        allow :update, when: guests <= capacity
      end

      assert validate_model!([InlinePolicyFixture37], []) == :ok
    end

    test "rejects multiple user entity designations" do
      defmodule InlinePolicyFixture27 do
        use Hologram.Entity, user: true
      end

      defmodule InlinePolicyFixture28 do
        use Hologram.Entity, user: true
      end

      expected_msg =
        "multiple user entity designations in the data model: Hologram.Policy.ValidatorTest.InlinePolicyFixture27, Hologram.Policy.ValidatorTest.InlinePolicyFixture28 - exactly one entity type can be designated with use Hologram.Entity, user: true"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture28, InlinePolicyFixture27], [])
      end
    end

    test "rejects role declarations without a user entity designation" do
      defmodule InlinePolicyFixture29 do
        use Hologram.Entity

        role :owner
      end

      expected_msg =
        "Hologram.Policy.ValidatorTest.InlinePolicyFixture29 declares roles or policy grant references, but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture29], [])
      end
    end

    test "rejects a to option without a user entity designation" do
      defmodule InlinePolicyFixture30 do
        use Hologram.Entity

        allow :update, to: {:editor, Module13}
      end

      expected_msg =
        "Hologram.Policy.ValidatorTest.InlinePolicyFixture30 declares roles or policy grant references, but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture30], [])
      end
    end

    test "rejects a condition naming user_id() without a user entity designation" do
      defmodule InlinePolicyFixture127 do
        use Hologram.Entity

        attribute :author_id, :uuid

        allow :read, when: author_id == user_id()
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture127 - it names user_id(), but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture127], [])
      end
    end

    test "rejects user_id() in an alternative without a user entity designation" do
      defmodule InlinePolicyFixture128 do
        use Hologram.Entity

        attribute :author_id, :uuid
        attribute :shared, :boolean

        allow :update, as: :edit, when: shared == true or author_id == user_id()
      end

      expected_msg =
        "invalid predicate for allow :update, as: :edit in Hologram.Policy.ValidatorTest.InlinePolicyFixture128 - it names user_id(), but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture128], [])
      end
    end

    test "rejects user_id() in a quantifier nested in another without a user entity designation" do
      defmodule InlinePolicyFixture129 do
        use Hologram.Entity

        attribute :author_id, :uuid

        relationship :children, [Hologram.Policy.ValidatorTest.InlinePolicyFixture129],
          inverse: parent

        relationship :parent, Hologram.Policy.ValidatorTest.InlinePolicyFixture129, optional: true

        allow :delete,
          when:
            any(
              child <- children,
              none(grandchild <- child.children, grandchild.author_id == user_id())
            )
      end

      expected_msg =
        "invalid predicate for allow :delete in Hologram.Policy.ValidatorTest.InlinePolicyFixture129 - it names user_id(), but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture129], [])
      end
    end

    test "rejects user_id() in a quantifier without a user entity designation" do
      defmodule InlinePolicyFixture131 do
        use Hologram.Entity

        relationship :children, [Hologram.Policy.ValidatorTest.InlinePolicyFixture131],
          inverse: parent

        relationship :owner, Hologram.Test.Fixtures.Entity.Module1, optional: true

        relationship :parent, Hologram.Policy.ValidatorTest.InlinePolicyFixture131, optional: true

        allow :read, when: any(child <- children, child.owner_id == user_id())
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture131 - it names user_id(), but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module1, InlinePolicyFixture131], [])
      end
    end

    test "rejects a field-limited line naming user_id() without a user entity designation" do
      defmodule InlinePolicyFixture132 do
        use Hologram.Entity

        attribute :author_id, :uuid
        attribute :title, :string

        allow :update, only: [:title], when: author_id == user_id()
      end

      expected_msg =
        "invalid predicate for allow :update, only: [:title] in Hologram.Policy.ValidatorTest.InlinePolicyFixture132 - it names user_id(), but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture132], [])
      end
    end

    test "accepts a condition naming user_id() with a user entity designation" do
      defmodule InlinePolicyFixture130 do
        use Hologram.Entity

        attribute :author_id, :uuid

        allow :read, when: author_id == user_id()
      end

      assert validate_model!([Module14, InlinePolicyFixture130], []) == :ok
    end

    test "rejects a global role module without a user entity designation" do
      expected_msg =
        "Hologram.Test.Fixtures.Role.Module1 is a global role, but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module2], [Role.Module1])
      end
    end

    test "accepts a global role module with a user entity designation" do
      assert validate_model!([Module14], [Role.Module1]) == :ok
    end

    test "rejects an actor leaf on a non-uuid attribute" do
      defmodule InlinePolicyFixture8 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, when: title == user_id()
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture8 - user_id() requires a uuid attribute - attribute :title in Hologram.Policy.ValidatorTest.InlinePolicyFixture8 has type :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture8], [])
      end
    end

    test "names a field-limited line with its fields" do
      defmodule LimitedUndeclaredRoleFixture do
        use Hologram.Entity

        attribute :title, :string, optional: true
        attribute :topic, :string, optional: true

        role :owner

        allow :update, only: [:title], to: :owner
        allow :update, only: [:topic], to: :ownr
      end

      expected_msg =
        "unknown role :ownr in the to option of allow :update, only: [:topic] in Hologram.Policy.ValidatorTest.LimitedUndeclaredRoleFixture - declared roles are: :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, LimitedUndeclaredRoleFixture], [])
      end
    end

    test "names a named field-limited line taken from a policy by its name, then its fields" do
      defmodule LimitedNamedUndeclaredRolePolicy do
        use Hologram.Policy

        allow :update, as: :retitle, only: [:title], to: :ownr
      end

      defmodule LimitedNamedUndeclaredRoleFixture do
        use Hologram.Entity

        attribute :title, :string, optional: true

        role :owner

        policy LimitedNamedUndeclaredRolePolicy
      end

      expected_msg =
        "unknown role :ownr in the to option of allow :update, as: :retitle, only: [:title] in Hologram.Policy.ValidatorTest.LimitedNamedUndeclaredRoleFixture, taken from Hologram.Policy.ValidatorTest.LimitedNamedUndeclaredRolePolicy - declared roles are: :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, LimitedNamedUndeclaredRoleFixture], [])
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
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture11 - declared roles are: :editor, :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture11], [])
      end
    end

    test "rejects a to option referencing a non-entity module" do
      defmodule InlinePolicyFixture15 do
        use Hologram.Entity

        allow :update, to: {:editor, Hologram.Reflection}
      end

      expected_msg =
        "invalid to option {:editor, Hologram.Reflection} for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture15 - Hologram.Reflection is not an entity type module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture15], [])
      end
    end

    test "rejects a to option referencing an undeclared role of another entity type" do
      defmodule InlinePolicyFixture16 do
        use Hologram.Entity

        allow :update, to: {:publisher, Module13}
      end

      expected_msg =
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture16 - declared roles of Hologram.Test.Fixtures.Entity.Module13 are: :editor, :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture16], [])
      end
    end

    test "rejects a to option naming an unknown relationship" do
      defmodule InlinePolicyFixture18 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :update, to: {:editor, project}
      end

      expected_msg =
        "unknown relationship :project in the to option of allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture18 - declared relationships are: :parent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture18], [])
      end
    end

    test "rejects a to option referencing a role on a to-many relationship" do
      defmodule InlinePolicyFixture19 do
        use Hologram.Entity

        relationship :children, [Module13]

        allow :update, to: {:editor, children}
      end

      expected_msg =
        "invalid to option {:editor, :children} for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture19 - relationship :children is to-many, but a role reference requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture19], [])
      end
    end

    test "rejects a to option referencing an undeclared role on a relationship target" do
      defmodule InlinePolicyFixture20 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :update, to: {:publisher, parent}
      end

      expected_msg =
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture20 - declared roles of Hologram.Test.Fixtures.Entity.Module13 are: :editor, :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture20], [])
      end
    end

    test "rejects a to option referencing a role on an inverse relationship" do
      defmodule InlinePolicyFixture76 do
        use Hologram.Entity

        relationship :topic, Hologram.Policy.ValidatorTest.InlinePolicyFixture80, inverse: channel

        allow :update, to: {:editor, topic}
      end

      defmodule InlinePolicyFixture80 do
        use Hologram.Entity

        relationship :channel, Hologram.Policy.ValidatorTest.InlinePolicyFixture76, unique: true
      end

      expected_msg =
        "invalid to option {:editor, :topic} for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture76 - relationship :topic is an inverse that reads the channel_id reference of Hologram.Policy.ValidatorTest.InlinePolicyFixture80, but a role reference requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture76, InlinePolicyFixture80], [])
      end
    end

    test "rejects a to option through a path reaching an inverse relationship on a later hop" do
      defmodule InlinePolicyFixture81 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module26

        relationship :channel, Module26

        allow :update, to: {:editor, channel.topic}
      end

      expected_msg =
        "invalid to option {:editor, channel.topic} for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture81 - relationship :topic in Hologram.Test.Fixtures.Entity.Module26 is an inverse that reads the channel_id reference of Hologram.Test.Fixtures.Entity.Module27, but a role reference requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture81], [])
      end
    end

    test "rejects a to option through a path with a to-many relationship on a later hop" do
      defmodule InlinePolicyFixture56 do
        use Hologram.Entity

        relationship :children, [Module13]
      end

      defmodule InlinePolicyFixture55 do
        use Hologram.Entity

        relationship :group, Hologram.Policy.ValidatorTest.InlinePolicyFixture56

        allow :update, to: {:editor, group.children}
      end

      expected_msg =
        "invalid to option {:editor, group.children} for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture55 - relationship :children in Hologram.Policy.ValidatorTest.InlinePolicyFixture56 is to-many, but a role reference requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture55, InlinePolicyFixture56], [])
      end
    end

    test "rejects a to option through a path with an unknown relationship on a later hop" do
      defmodule InlinePolicyFixture57 do
        use Hologram.Entity

        relationship :item, Hologram.Test.Fixtures.Entity.Module25

        allow :update, to: {:editor, item.project}
      end

      expected_msg =
        "unknown relationship :project in Hologram.Test.Fixtures.Entity.Module25 in the to option of allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture57 - declared relationships of Hologram.Test.Fixtures.Entity.Module25 are: :e, :f, :g, :h"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture57], [])
      end
    end

    test "rejects a to option naming a role the type a path ends at does not declare" do
      defmodule InlinePolicyFixture58 do
        use Hologram.Entity

        relationship :item, Hologram.Test.Fixtures.Entity.Module25

        allow :update, to: {:publisher, item.h}
      end

      expected_msg =
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture58 - declared roles of Hologram.Test.Fixtures.Entity.Module13 are: :editor, :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture58], [])
      end
    end

    test "rejects a via option naming an unknown relationship" do
      defmodule InlinePolicyFixture22 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :read, via: project
      end

      expected_msg =
        "unknown relationship :project in the via option of allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture22 - declared relationships are: :parent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture22], [])
      end
    end

    test "rejects a via option naming a to-many relationship" do
      defmodule InlinePolicyFixture23 do
        use Hologram.Entity

        relationship :children, [Module13]

        allow :read, via: children
      end

      expected_msg =
        "invalid via option :children for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture23 - relationship :children is to-many, but delegation requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture23], [])
      end
    end

    test "rejects a via option naming an inverse relationship" do
      defmodule InlinePolicyFixture75 do
        use Hologram.Entity

        relationship :topic, Hologram.Policy.ValidatorTest.InlinePolicyFixture77, inverse: channel

        allow :read, via: topic
      end

      defmodule InlinePolicyFixture77 do
        use Hologram.Entity

        relationship :channel, Hologram.Policy.ValidatorTest.InlinePolicyFixture75, unique: true
      end

      expected_msg =
        "invalid via option :topic for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture75 - relationship :topic is an inverse that reads the channel_id reference of Hologram.Policy.ValidatorTest.InlinePolicyFixture77, but delegation requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture75, InlinePolicyFixture77], [])
      end
    end

    test "rejects a via option through a path reaching an inverse relationship on a later hop" do
      defmodule InlinePolicyFixture78 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module26

        relationship :channel, Module26

        allow :read, via: channel.topic
      end

      expected_msg =
        "invalid via option channel.topic for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture78 - relationship :topic in Hologram.Test.Fixtures.Entity.Module26 is an inverse that reads the channel_id reference of Hologram.Test.Fixtures.Entity.Module27, but delegation requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture78], [])
      end
    end

    test "rejects a condition through a path reaching an inverse relationship" do
      defmodule InlinePolicyFixture79 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module26

        relationship :channel, Module26

        allow :read, when: channel.topic.summary == "x"
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture79 - :topic is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - a path in a condition goes through to-one relationships that hold their reference"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture79], [])
      end
    end

    test "rejects a via option naming a derived field" do
      defmodule InlinePolicyFixture86 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32
        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :channel, Module32

        derived :first_message, Module33, fn channel -> one(channel.messages) end

        allow :read, via: first_message
      end

      expected_msg =
        "invalid via option :first_message for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture86 - :first_message is a derived field, but delegation requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture86], [])
      end
    end

    test "rejects a via option through a path reaching a derived field on a later hop" do
      defmodule InlinePolicyFixture87 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32

        relationship :channel, Module32

        allow :read, via: channel.first_message
      end

      expected_msg =
        "invalid via option channel.first_message for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture87 - :first_message in Hologram.Test.Fixtures.Entity.Module32 is a derived field, but delegation requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture87], [])
      end
    end

    test "rejects a to option referencing a role on a derived field" do
      defmodule InlinePolicyFixture88 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32
        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :channel, Module32

        derived :first_message, Module33, fn channel -> one(channel.messages) end

        allow :update, to: {:editor, first_message}
      end

      expected_msg =
        "invalid to option {:editor, :first_message} for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture88 - :first_message is a derived field, but a role reference requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture88], [])
      end
    end

    test "rejects a to option through a path reaching a derived field on a later hop" do
      defmodule InlinePolicyFixture89 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32

        relationship :channel, Module32

        allow :update, to: {:editor, channel.first_message}
      end

      expected_msg =
        "invalid to option {:editor, channel.first_message} for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture89 - :first_message in Hologram.Test.Fixtures.Entity.Module32 is a derived field, but a role reference requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture89], [])
      end
    end

    test "rejects a via option through a path starting with a to-many relationship" do
      defmodule InlinePolicyFixture65 do
        use Hologram.Entity

        relationship :children, [Module13]

        allow :read, via: children.parent
      end

      expected_msg =
        "invalid via option children.parent for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture65 - relationship :children is to-many, but delegation requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture65], [])
      end
    end

    test "rejects a via option that is not a relationship name" do
      defmodule InlinePolicyFixture24 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :read, via: ^"parent"
      end

      expected_msg =
        "invalid via option \"parent\" for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture24 - the via option must be a relationship name, a path, or an {operation, relationship} tuple"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture24], [])
      end
    end

    test "rejects a via option that is a list of one relationship name" do
      defmodule InlinePolicyFixture53 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :read, via: ^[:parent]
      end

      expected_msg =
        "invalid via option [:parent] for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture53 - the via option must be a relationship name, a path, or an {operation, relationship} tuple"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture53], [])
      end
    end

    test "rejects a via option naming its operation and an unknown relationship" do
      defmodule InlinePolicyFixture43 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :read, via: {:update, project}
      end

      expected_msg =
        "unknown relationship :project in the via option of allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture43 - declared relationships are: :parent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture43], [])
      end
    end

    test "rejects a via option naming its operation with something other than an atom" do
      defmodule InlinePolicyFixture44 do
        use Hologram.Entity

        relationship :parent, Module13

        allow :read, via: ^{"update", :parent}
      end

      expected_msg =
        ~s(invalid via option {"update", :parent} for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture44 - the via option must be a relationship name, a path, or an {operation, relationship} tuple)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture44], [])
      end
    end

    test "rejects a via option naming its operation and one the related entity type can't be asked about" do
      defmodule InlinePolicyFixture49 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :create, via: {:udpate, parent}
      end

      expected_msg =
        "invalid via option {:udpate, :parent} for allow :create in Hologram.Policy.ValidatorTest.InlinePolicyFixture49 - unknown operation :udpate for Hologram.Test.Fixtures.Entity.Module1 - the framework's operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update, and its allow lines carry no name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture49], [])
      end
    end

    test "rejects a via option through a path with a to-many relationship on a later hop" do
      defmodule InlinePolicyFixture61 do
        use Hologram.Entity

        relationship :children, [Module13]
      end

      defmodule InlinePolicyFixture60 do
        use Hologram.Entity

        relationship :group, Hologram.Policy.ValidatorTest.InlinePolicyFixture61

        allow :read, via: group.children
      end

      expected_msg =
        "invalid via option group.children for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture60 - relationship :children in Hologram.Policy.ValidatorTest.InlinePolicyFixture61 is to-many, but delegation requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture60, InlinePolicyFixture61], [])
      end
    end

    test "rejects a via option through a path with an unknown relationship on a later hop" do
      defmodule InlinePolicyFixture59 do
        use Hologram.Entity

        relationship :item, Hologram.Test.Fixtures.Entity.Module25

        allow :read, via: item.project
      end

      expected_msg =
        "unknown relationship :project in Hologram.Test.Fixtures.Entity.Module25 in the via option of allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture59 - declared relationships of Hologram.Test.Fixtures.Entity.Module25 are: :e, :f, :g, :h"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture59], [])
      end
    end

    test "rejects a via option through a path asking an operation the type it ends at can't be asked about" do
      defmodule InlinePolicyFixture62 do
        use Hologram.Entity

        relationship :item, Module13

        allow :update, as: :publish, via: {:publish, item.parent}
      end

      expected_msg =
        "invalid via option {:publish, item.parent} for allow :update, as: :publish in Hologram.Policy.ValidatorTest.InlinePolicyFixture62 - unknown operation :publish for Hologram.Test.Fixtures.Entity.Module1 - the framework's operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update, and its allow lines carry no name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture62], [])
      end
    end

    test "rejects a delegation cycle spanning two entity types" do
      defmodule InlinePolicyFixture25 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.InlinePolicyFixture26, optional: true

        allow :read, via: peer
      end

      defmodule InlinePolicyFixture26 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.InlinePolicyFixture25, optional: true

        allow :read, via: peer
      end

      expected_msg =
        normalize_newlines("""
        cyclic policy delegation for allow :read - a via chain can't return to the entity type it starts from:
          * Hologram.Policy.ValidatorTest.InlinePolicyFixture25 (via :peer) -> Hologram.Policy.ValidatorTest.InlinePolicyFixture26 (via :peer) -> Hologram.Policy.ValidatorTest.InlinePolicyFixture25\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture25, InlinePolicyFixture26], [])
      end
    end

    # The create asks the other type's update, which asks the first type's create again.
    test "rejects a delegation cycle across operations" do
      defmodule InlinePolicyFixture45 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.InlinePolicyFixture46, optional: true

        allow :create, via: {:update, peer}
      end

      defmodule InlinePolicyFixture46 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.InlinePolicyFixture45, optional: true

        allow :update, via: {:create, peer}
      end

      expected_msg =
        normalize_newlines("""
        cyclic policy delegation for allow :create - a via chain can't return to the entity type it starts from:
          * Hologram.Policy.ValidatorTest.InlinePolicyFixture45 (via {:update, :peer}) -> Hologram.Policy.ValidatorTest.InlinePolicyFixture46 (via {:create, :peer}) -> Hologram.Policy.ValidatorTest.InlinePolicyFixture45\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture45, InlinePolicyFixture46], [])
      end
    end

    test "rejects a delegation cycle through a path" do
      defmodule InlinePolicyFixture63 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.InlinePolicyFixture64, optional: true

        allow :read, via: peer.peer
      end

      defmodule InlinePolicyFixture64 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.InlinePolicyFixture63, optional: true
      end

      expected_msg =
        normalize_newlines("""
        cyclic policy delegation for allow :read - a via chain can't return to the entity type it starts from:
          * Hologram.Policy.ValidatorTest.InlinePolicyFixture63 (via peer.peer) -> Hologram.Policy.ValidatorTest.InlinePolicyFixture63\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture63, InlinePolicyFixture64], [])
      end
    end

    test "rejects a condition path through a type nobody may read" do
      defmodule InlinePolicyFixture67 do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        allow :create
      end

      defmodule InlinePolicyFixture68 do
        use Hologram.Entity

        relationship :parent, Hologram.Policy.ValidatorTest.InlinePolicyFixture67

        allow :update, when: parent.archived == false
      end

      expected_msg =
        "allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture68 reads Hologram.Policy.ValidatorTest.InlinePolicyFixture67 through parent, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.InlinePolicyFixture67: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture67, InlinePolicyFixture68], [])
      end
    end

    # The role is looked up by the id the last relationship holds, read off the row before it - so
    # the row before it has to reach the browser, and the one at the end does not.
    test "rejects a role reference read through a type nobody may read" do
      defmodule InlinePolicyFixture69 do
        use Hologram.Entity

        relationship :group, Hologram.Test.Fixtures.Policy.Module2

        allow :create
      end

      defmodule InlinePolicyFixture70 do
        use Hologram.Entity

        relationship :parent, Hologram.Policy.ValidatorTest.InlinePolicyFixture69

        allow :delete, to: {:admin, parent.group}
      end

      expected_msg =
        "allow :delete in Hologram.Policy.ValidatorTest.InlinePolicyFixture70 reads Hologram.Policy.ValidatorTest.InlinePolicyFixture69 through parent, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.InlinePolicyFixture69: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture69, InlinePolicyFixture70], [])
      end
    end

    test "rejects a non-read rule's any over a set of a type nobody may read" do
      defmodule InlinePolicyFixture104 do
        use Hologram.Entity

        attribute :taken, :boolean

        allow :create
      end

      defmodule InlinePolicyFixture105 do
        use Hologram.Entity

        relationship :seats, [Hologram.Policy.ValidatorTest.InlinePolicyFixture104]

        allow :update, when: any(seat <- seats, seat.taken == true)
      end

      expected_msg =
        "allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture105 reads Hologram.Policy.ValidatorTest.InlinePolicyFixture104 through seats, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.InlinePolicyFixture104: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture104, InlinePolicyFixture105], [])
      end
    end

    # A row reaches the browser only once the server's read rules admitted it.
    test "accepts a read rule's any over a set of a type nobody may read" do
      defmodule InlinePolicyFixture111 do
        use Hologram.Entity

        attribute :taken, :boolean

        allow :create
      end

      defmodule InlinePolicyFixture106 do
        use Hologram.Entity

        relationship :seats, [Hologram.Policy.ValidatorTest.InlinePolicyFixture111]

        allow :read, when: any(seat <- seats, seat.taken == true)
      end

      assert validate_model!([InlinePolicyFixture111, InlinePolicyFixture106], []) == :ok
    end

    # The server's verdict answers a none over the rows as stored, so no browser reads them.
    test "accepts a non-read rule's none over a set of a type nobody may read" do
      defmodule InlinePolicyFixture112 do
        use Hologram.Entity

        attribute :taken, :boolean

        allow :create
      end

      defmodule InlinePolicyFixture107 do
        use Hologram.Entity

        relationship :seats, [Hologram.Policy.ValidatorTest.InlinePolicyFixture112]

        allow :update, when: none(seat <- seats, seat.taken == true)
      end

      assert validate_model!([InlinePolicyFixture112, InlinePolicyFixture107], []) == :ok
    end

    # The delegated read rule's server-only path is answered from the server's verdict on the
    # related row, which a browser holds as it was sent, so no browser reads the row beyond it.
    test "accepts a delegation to a read rule whose server-only path runs through a type nobody may read" do
      defmodule InlinePolicyFixture124 do
        use Hologram.Entity

        attribute :secret, :boolean, server_only: true

        allow :create
      end

      defmodule InlinePolicyFixture125 do
        use Hologram.Entity

        relationship :owner, Hologram.Policy.ValidatorTest.InlinePolicyFixture124

        allow :read, when: owner.secret == true
      end

      defmodule InlinePolicyFixture126 do
        use Hologram.Entity

        relationship :report, Hologram.Policy.ValidatorTest.InlinePolicyFixture125

        allow :read
        allow :update, via: {:read, report}
      end

      types = [InlinePolicyFixture124, InlinePolicyFixture125, InlinePolicyFixture126]

      assert validate_model!(types, []) == :ok
    end

    # The delegated read rule's path is answered from the server's verdict on the related row, which
    # a browser holds as it was sent, so no browser reads the row beyond it.
    test "accepts a delegation to a read rule whose path runs through a type nobody may read" do
      defmodule InlinePolicyFixture129 do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        allow :create
      end

      defmodule InlinePolicyFixture130 do
        use Hologram.Entity

        relationship :project, Hologram.Policy.ValidatorTest.InlinePolicyFixture129

        allow :read, when: project.archived == false
      end

      defmodule InlinePolicyFixture131 do
        use Hologram.Entity

        relationship :task, Hologram.Policy.ValidatorTest.InlinePolicyFixture130

        allow :read
        allow :update, via: {:read, task}
      end

      types = [InlinePolicyFixture129, InlinePolicyFixture130, InlinePolicyFixture131]

      assert validate_model!(types, []) == :ok
    end

    # The delegated read rule's role reference is answered from the server's verdict on the related
    # row, so no browser reads the row it reads the team's id off.
    test "accepts a delegation to a read rule whose role reference runs through a type nobody may read" do
      defmodule InlinePolicyFixture132 do
        use Hologram.Entity

        role :member

        allow :read
      end

      defmodule InlinePolicyFixture133 do
        use Hologram.Entity

        relationship :team, Hologram.Policy.ValidatorTest.InlinePolicyFixture132

        allow :create
      end

      defmodule InlinePolicyFixture134 do
        use Hologram.Entity

        relationship :project, Hologram.Policy.ValidatorTest.InlinePolicyFixture133

        allow :read, to: {:member, project.team}
      end

      defmodule InlinePolicyFixture135 do
        use Hologram.Entity

        relationship :task, Hologram.Policy.ValidatorTest.InlinePolicyFixture134

        allow :read
        allow :update, via: {:read, task}
      end

      types = [
        Module14,
        InlinePolicyFixture132,
        InlinePolicyFixture133,
        InlinePolicyFixture134,
        InlinePolicyFixture135
      ]

      assert validate_model!(types, []) == :ok
    end

    # The validator asks whether the delegated read rule's any is deciding before the build resolves
    # the card's derived field, so the answer comes from the field's own definition.
    test "accepts a delegation to a read rule whose any reads a derived value before it resolves" do
      defmodule InlinePolicyFixture139 do
        use Hologram.Entity

        attribute :score, :integer

        relationship :board, Hologram.Policy.ValidatorTest.InlinePolicyFixture140, optional: true

        derived :hot, :boolean, fn score -> score > 3 end

        allow :read
      end

      defmodule InlinePolicyFixture140 do
        use Hologram.Entity

        relationship :cards, [InlinePolicyFixture139], inverse: board

        allow :read, when: any(card <- cards, card.hot == true)
      end

      defmodule InlinePolicyFixture141 do
        use Hologram.Entity

        relationship :board, InlinePolicyFixture140

        allow :read
        allow :update, via: {:read, board}
      end

      types = [InlinePolicyFixture139, InlinePolicyFixture140, InlinePolicyFixture141]

      assert validate_model!(types, []) == :ok
    end

    # The delegated read rule's own delegation is answered from the server's verdict on the related
    # row, so no browser reads the vault it leads to.
    test "accepts a delegation to a read rule whose delegation runs through a type nobody may read" do
      defmodule InlinePolicyFixture136 do
        use Hologram.Entity

        attribute :open, :boolean, default: false

        allow :update, when: open == true
      end

      defmodule InlinePolicyFixture137 do
        use Hologram.Entity

        relationship :vault, Hologram.Policy.ValidatorTest.InlinePolicyFixture136

        allow :read, via: {:update, vault}
      end

      defmodule InlinePolicyFixture138 do
        use Hologram.Entity

        relationship :parcel, Hologram.Policy.ValidatorTest.InlinePolicyFixture137

        allow :read
        allow :update, via: {:read, parcel}
      end

      types = [InlinePolicyFixture136, InlinePolicyFixture137, InlinePolicyFixture138]

      assert validate_model!(types, []) == :ok
    end

    test "accepts a non-read rule's none through a row of a type nobody may read" do
      defmodule InlinePolicyFixture113 do
        use Hologram.Entity

        attribute :taken, :boolean

        allow :create
      end

      defmodule InlinePolicyFixture114 do
        use Hologram.Entity

        relationship :seats, [Hologram.Policy.ValidatorTest.InlinePolicyFixture113]

        allow :create
      end

      defmodule InlinePolicyFixture108 do
        use Hologram.Entity

        relationship :parent, Hologram.Policy.ValidatorTest.InlinePolicyFixture114

        allow :delete, when: none(seat <- parent.seats, seat.taken == true)
      end

      assert validate_model!(
               [InlinePolicyFixture113, InlinePolicyFixture114, InlinePolicyFixture108],
               []
             ) == :ok
    end

    # The path reads the parent in the browser, whatever the none beside it reads.
    test "rejects a row of a type nobody may read that a path reads beside a deciding quantifier" do
      defmodule InlinePolicyFixture119 do
        use Hologram.Entity

        attribute :taken, :boolean

        allow :read
      end

      defmodule InlinePolicyFixture120 do
        use Hologram.Entity

        attribute :name, :string

        relationship :seats, [Hologram.Policy.ValidatorTest.InlinePolicyFixture119]

        allow :create
      end

      defmodule InlinePolicyFixture121 do
        use Hologram.Entity

        relationship :parent, Hologram.Policy.ValidatorTest.InlinePolicyFixture120

        allow :update,
          when: parent.name == "x" and none(seat <- parent.seats, seat.taken == true)
      end

      expected_msg =
        "allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture121 reads Hologram.Policy.ValidatorTest.InlinePolicyFixture120 through parent, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.InlinePolicyFixture120: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!(
          [InlinePolicyFixture119, InlinePolicyFixture120, InlinePolicyFixture121],
          []
        )
      end
    end

    # Delegating to a read rule is not a read rule: the browser decides it by running the related
    # type's read rules over the related row, which it has to hold.
    test "rejects a delegation to a read rule through a type nobody may read" do
      defmodule InlinePolicyFixture71 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :update, as: :publish, via: {:read, parent}
      end

      expected_msg =
        "allow :update, as: :publish in Hologram.Policy.ValidatorTest.InlinePolicyFixture71 reads Hologram.Test.Fixtures.Entity.Module1 through parent, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Test.Fixtures.Entity.Module1: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture71], [])
      end
    end

    test "rejects a type nobody may read along a delegation's chain" do
      defmodule InlinePolicyFixture72 do
        use Hologram.Entity

        attribute :locked, :boolean, default: false

        allow :create
      end

      defmodule InlinePolicyFixture73 do
        use Hologram.Entity

        relationship :settings, Hologram.Policy.ValidatorTest.InlinePolicyFixture72

        allow :read
        allow :update, when: settings.locked == false
      end

      defmodule InlinePolicyFixture74 do
        use Hologram.Entity

        relationship :project, Hologram.Policy.ValidatorTest.InlinePolicyFixture73

        allow :update, via: project
      end

      expected_msg =
        "allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture74 reads Hologram.Policy.ValidatorTest.InlinePolicyFixture72 through project.settings, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.InlinePolicyFixture72: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture74], [])
      end
    end

    test "rejects a predicate naming a field only the quantifier's row declares, naming how to read it" do
      defmodule InlinePolicyFixture142 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :messages, [Module33]

        allow :read, when: any(message <- messages, position > 1)
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture142 - unknown attribute :position in Hologram.Policy.ValidatorTest.InlinePolicyFixture142 - known attributes: :created_at, :id, :server_created_at, :server_updated_at, :updated_at - Hologram.Test.Fixtures.Entity.Module33 declares position, read as message.position"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture142], [])
      end
    end

    test "rejects a predicate naming an unknown attribute" do
      defmodule InlinePolicyFixture3 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, when: published == true
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture3 - unknown attribute :published in Hologram.Policy.ValidatorTest.InlinePolicyFixture3 - known attributes: :created_at, :id, :server_created_at, :server_updated_at, :title, :updated_at"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture3], [])
      end
    end

    test "rejects a predicate naming a relationship" do
      defmodule InlinePolicyFixture4 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, when: parent == nil
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture4 - :parent is a relationship in Hologram.Policy.ValidatorTest.InlinePolicyFixture4 - only attributes can be filtered - filter its reference via :parent_id"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture4], [])
      end
    end

    test "rejects a predicate using an unknown operator" do
      defmodule InlinePolicyFixture5 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, when: ^[title: {:like, "text_1"}]
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture5 - unknown operator :like in the filter predicate for attribute :title - supported operators: :!=, :<, :<=, :==, :>, :>=, :contains, :contains_exact, :in, :not_in, :starts_with, :starts_with_exact"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture5], [])
      end
    end

    test "accepts a quantifier in a pinned condition" do
      defmodule InlinePolicyFixture82 do
        use Hologram.Entity

        relationship :items, [Module2]

        allow :read, when: ^[any: {[:items], []}]
      end

      assert validate_model!([InlinePolicyFixture82], []) == :ok
    end

    test "accepts a quantifier inside an alternative of a pinned condition" do
      defmodule InlinePolicyFixture83 do
        use Hologram.Entity

        attribute :title, :string

        relationship :items, [Module2]

        allow :read, when: ^[or: [[title: "a"], [any: {[:items], []}]]]
      end

      assert validate_model!([InlinePolicyFixture83], []) == :ok
    end

    test "accepts a condition comparing a derived field that reads no related set" do
      defmodule InlinePolicyFixture90 do
        use Hologram.Entity

        attribute :title, :string

        derived :heading, :string, fn title -> title end

        allow :read, when: heading == "x"
      end

      assert validate_model!([InlinePolicyFixture90], []) == :ok
    end

    test "accepts a condition comparing with a derived field that reads no related set" do
      defmodule InlinePolicyFixture91 do
        use Hologram.Entity

        attribute :title, :string

        derived :heading, :string, fn title -> title end

        allow :read, when: title == heading
      end

      assert validate_model!([InlinePolicyFixture91], []) == :ok
    end

    test "rejects a condition through a path ending at a derived field counting a related set" do
      defmodule InlinePolicyFixture92 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32

        relationship :channel, Module32

        allow :read, when: channel.message_count > 3
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture92 - channel.message_count counts messages - a policy condition reads a related set only through any, none or all"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture92], [])
      end
    end

    test "rejects a condition through a path reaching a derived field on a later hop" do
      defmodule InlinePolicyFixture93 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32

        relationship :channel, Module32

        allow :read, when: channel.first_message.body == "x"
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture93 - :first_message is a derived field in Hologram.Test.Fixtures.Entity.Module32 - a path in a condition goes through to-one relationships that hold their reference"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture93], [])
      end
    end

    test "accepts a derived field inside an alternative of a condition" do
      defmodule InlinePolicyFixture94 do
        use Hologram.Entity

        attribute :title, :string

        derived :heading, :string, fn title -> title end

        allow :read, when: title == "x" or heading == "y"
      end

      assert validate_model!([InlinePolicyFixture94], []) == :ok
    end

    test "rejects an ordering comparison with a derived string in an operator list of a pinned condition" do
      defmodule InlinePolicyFixture96 do
        use Hologram.Entity

        attribute :title, :string

        derived :heading, :string, fn title -> title end

        allow :read, when: ^[title: [{:>, {:attribute, :heading}}, {:<, "z"}]]
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture96 - operator :> requires an orderable attribute - :heading in Hologram.Policy.ValidatorTest.InlinePolicyFixture96 is a derived string, and a string compares by the sort key stored with it, which a computed string has none of"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture96], [])
      end
    end

    test "rejects a condition through a to-many relationship before the derived field it reaches" do
      defmodule InlinePolicyFixture97 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :notes, [Module33]

        allow :read, when: notes.channel_name == "x"
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture97 - :notes is a to-many relationship in Hologram.Policy.ValidatorTest.InlinePolicyFixture97 - a path in a condition goes through to-one relationships only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture97], [])
      end
    end

    # The browser never answers it over rows it holds, so nothing a row hides misleads it.
    test "accepts a non-read rule's any over a derived set with a condition" do
      defmodule InlinePolicyFixture115 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32

        relationship :channel, Module32

        allow :update, when: any(message <- channel.recent_messages, message.position == 1)
      end

      assert validate_model!([InlinePolicyFixture115], []) == :ok
    end

    test "rejects a derived field holding a value as a quantifier's source" do
      defmodule InlinePolicyFixture116 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :messages, [Module33]

        derived :message_total, :integer, fn messages -> count(messages) end

        allow :update, when: ^[any: {[:message_total], [position: 1]}]
      end

      expected_msg =
        "invalid predicate for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture116 - :message_total is a derived field holding a :integer value in Hologram.Policy.ValidatorTest.InlinePolicyFixture116 - any, none and all ask about the rows of a set"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture116], [])
      end
    end

    test "accepts a quantifier over a derived set in a pinned condition" do
      defmodule InlinePolicyFixture95 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32

        relationship :channel, Module32

        allow :read, when: ^[any: {[:channel, :recent_messages], []}]
      end

      assert validate_model!([InlinePolicyFixture95], []) == :ok
    end

    test "accepts a condition comparing a concatenation over a to-one path" do
      defmodule InlinePolicyFixture98 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module32

        attribute :title, :string

        relationship :channel, Module32

        derived :label, :string, fn title, channel -> title <> " in " <> channel.name end

        allow :read, when: label == "news in general"
      end

      assert validate_model!([InlinePolicyFixture98], []) == :ok
    end

    test "accepts a condition comparing a boolean condition field" do
      defmodule InlinePolicyFixture99 do
        use Hologram.Entity

        attribute :score, :integer

        derived :active, :boolean, fn score -> score > 0 end

        allow :update, when: active == true
      end

      assert validate_model!([InlinePolicyFixture99], []) == :ok
    end

    test "accepts a condition comparing a derived field reading another that reads no related set" do
      defmodule InlinePolicyFixture100 do
        use Hologram.Entity

        attribute :title, :string

        derived :heading, :string, fn title -> title end

        derived :shout, :string, fn heading -> heading <> "!" end

        allow :read, when: shout == "x!"
      end

      assert validate_model!([InlinePolicyFixture100], []) == :ok
    end

    test "rejects a condition comparing a derived field that calls a query builder" do
      defmodule InlinePolicyFixture101 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module36

        relationship :member, Module36

        allow :read, when: member.unread_count > 0
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture101 - member.unread_count calls a query builder - a policy condition reads a related set only through any, none or all"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture101], [])
      end
    end

    # The server's verdict answers the any, so the build never runs the builder over a stand-in.
    test "accepts a non-read quantifier's condition comparing a derived field that calls a query builder" do
      defmodule InlinePolicyFixture122 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module36

        relationship :memberships, [Module36]

        allow :update, when: any(membership <- memberships, membership.unread_count > 0)
      end

      assert validate_model!([InlinePolicyFixture122], []) == :ok
    end

    test "rejects a non-read quantifier's condition comparing a derived field that reads a server-only attribute beside a count" do
      defmodule InlinePolicyFixture123Member do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        attribute :muted, :boolean, server_only: true

        relationship :messages, [Module33]

        derived :pending, :integer, fn muted, messages ->
          if muted == true, do: count(messages), else: 0
        end

        allow :read
      end

      defmodule InlinePolicyFixture123 do
        use Hologram.Entity

        alias Hologram.Policy.ValidatorTest.InlinePolicyFixture123Member

        relationship :members, [InlinePolicyFixture123Member]

        allow :update, when: all(member <- members, member.pending > 0)
      end

      expected_msg =
        "invalid predicate members.pending for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture123 - members.pending reads members.muted, which is server_only, and the client cannot decide :update locally over a value it never holds. Server-only predicates are legal on allow :read only, which a client answers from the server's verdict on the row it was sent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture123, InlinePolicyFixture123Member], [])
      end
    end

    test "rejects a condition comparing a derived field reading one that counts a related set" do
      defmodule InlinePolicyFixture102 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module37

        relationship :room, Module37

        allow :read, when: room.busy == true
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture102 - room.busy reads :pinned_count, which counts messages - a policy condition reads a related set only through any, none or all"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture102], [])
      end
    end

    test "rejects a non-read condition reading a server-only attribute through a derived field" do
      defmodule InlinePolicyFixture103 do
        use Hologram.Entity

        attribute :token, :string, server_only: true

        derived :masked, :string, fn token -> token end

        allow :update, when: masked == "x"
      end

      expected_msg =
        "invalid predicate :masked for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture103 - :masked reads :token, which is server_only, and the client cannot decide :update locally over a value it never holds. Server-only predicates are legal on allow :read only, which a client answers from the server's verdict on the row it was sent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture103], [])
      end
    end

    test "rejects a disjunction with one alternative in a pinned condition" do
      defmodule InlinePolicyFixture35 do
        use Hologram.Entity

        attribute :public, :boolean

        allow :read, when: ^[or: [[public: true]]]
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture35 - a disjunction takes a list of at least two predicate lists, got: [[public: true]]"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture35], [])
      end
    end

    test "rejects an ordering comparison on a to-one reference field" do
      defmodule InlinePolicyFixture6 do
        use Hologram.Entity

        relationship :parent, Module1

        allow :read, when: parent_id >= "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture6 - operator :>= requires an orderable attribute - attribute :parent_id in Hologram.Policy.ValidatorTest.InlinePolicyFixture6 has type :uuid, and boolean and uuid attributes have no order to compare by"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture6], [])
      end
    end

    test "rejects a condition comparing attributes of different types" do
      defmodule InlinePolicyFixture38 do
        use Hologram.Entity

        attribute :ends_at, :datetime
        attribute :starts_on, :date

        allow :update, when: ends_at < starts_on
      end

      expected_msg =
        "invalid predicate for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture38 - operator :< compares attribute :ends_at with attribute :starts_on in Hologram.Policy.ValidatorTest.InlinePolicyFixture38, which have different types (:datetime and :date) - two attributes compare when they have the same type, or when one widens to the other (:integer to :float)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture38], [])
      end
    end

    test "accepts a read predicate over a server-only attribute" do
      defmodule InlinePolicyFixture32 do
        use Hologram.Entity

        attribute :token, :string, server_only: true

        allow :read, when: token == "tok_hidden"
      end

      assert validate_model!([InlinePolicyFixture32], []) == :ok
    end

    test "accepts a read predicate over a server-only attribute through a path" do
      defmodule InlinePolicyFixture50 do
        use Hologram.Entity

        relationship :author, Module14

        allow :read, when: author.password_hash == nil
      end

      assert validate_model!([Module14, InlinePolicyFixture50], []) == :ok
    end

    test "accepts a non-read predicate over an attribute that is not server-only in this type" do
      defmodule InlinePolicyFixture31 do
        use Hologram.Entity

        attribute :token, :string

        allow :update, as: :publish, when: token == "tok_public"
      end

      assert validate_model!([InlinePolicyFixture31], []) == :ok
    end

    # Not a read line, so the server-only check walks the disjunction rather than skipping it.
    test "accepts a disjunction in a pinned condition" do
      defmodule InlinePolicyFixture34 do
        use Hologram.Entity

        attribute :priority, :integer
        attribute :public, :boolean

        allow :update, when: ^[or: [[public: true], [priority: {:>=, 3}]]]
      end

      assert validate_model!([InlinePolicyFixture34], []) == :ok
    end

    test "accepts a search in a condition" do
      defmodule InlinePolicyFixture84 do
        use Hologram.Entity

        attribute :path, :string

        allow :read, when: starts_with(path, "public/", mode: :exact)
      end

      assert validate_model!([InlinePolicyFixture84], []) == :ok
    end

    test "rejects a search on an attribute that is not a string" do
      defmodule InlinePolicyFixture85 do
        use Hologram.Entity

        attribute :priority, :integer

        allow :read, when: ^[priority: {:starts_with, "1"}]
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.InlinePolicyFixture85 - operator :starts_with requires a string attribute - attribute :priority in Hologram.Policy.ValidatorTest.InlinePolicyFixture85 has type :integer"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture85], [])
      end
    end

    test "rejects a non-read predicate over a server-only attribute" do
      defmodule InlinePolicyFixture33 do
        use Hologram.Entity

        attribute :token, :string, server_only: true

        allow :update, as: :publish, when: token == "tok_hidden"
      end

      expected_msg =
        "invalid predicate :token for allow :update, as: :publish in Hologram.Policy.ValidatorTest.InlinePolicyFixture33 - :token is server_only, and the client cannot decide :publish locally over a value it never holds. Server-only predicates are legal on allow :read only, which a client answers from the server's verdict on the row it was sent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture33], [])
      end
    end

    test "rejects a non-read quantifier's condition over a server-only attribute of the set's rows" do
      defmodule InlinePolicyFixture109 do
        use Hologram.Entity

        attribute :code, :string, server_only: true

        allow :read
      end

      defmodule InlinePolicyFixture110 do
        use Hologram.Entity

        relationship :seats, [Hologram.Policy.ValidatorTest.InlinePolicyFixture109]

        allow :update, when: any(seat <- seats, seat.code == "x")
      end

      expected_msg =
        "invalid predicate seats.code for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture110 - seats.code is server_only, and the client cannot decide :update locally over a value it never holds. Server-only predicates are legal on allow :read only, which a client answers from the server's verdict on the row it was sent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture109, InlinePolicyFixture110], [])
      end
    end

    # The browser checks a none over the rows it holds before the verdict, and those hold no value
    # for the attribute.
    test "rejects a non-read none's condition over a server-only attribute of the set's rows" do
      defmodule InlinePolicyFixture117 do
        use Hologram.Entity

        attribute :code, :string, server_only: true

        allow :read
      end

      defmodule InlinePolicyFixture118 do
        use Hologram.Entity

        relationship :seats, [Hologram.Policy.ValidatorTest.InlinePolicyFixture117]

        allow :update, when: none(seat <- seats, seat.code == "x")
      end

      expected_msg =
        "invalid predicate seats.code for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture118 - seats.code is server_only, and the client cannot decide :update locally over a value it never holds. Server-only predicates are legal on allow :read only, which a client answers from the server's verdict on the row it was sent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture117, InlinePolicyFixture118], [])
      end
    end

    test "rejects a non-read predicate over a server-only attribute through a path" do
      defmodule InlinePolicyFixture51 do
        use Hologram.Entity

        relationship :author, Module14

        allow :update, when: author.password_hash == nil
      end

      expected_msg =
        "invalid predicate author.password_hash for allow :update in Hologram.Policy.ValidatorTest.InlinePolicyFixture51 - author.password_hash is server_only, and the client cannot decide :update locally over a value it never holds. Server-only predicates are legal on allow :read only, which a client answers from the server's verdict on the row it was sent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InlinePolicyFixture51], [])
      end
    end

    test "rejects a non-read predicate over a server-only attribute inside a disjunction" do
      defmodule InlinePolicyFixture36 do
        use Hologram.Entity

        attribute :label, :string
        attribute :token, :string, server_only: true

        allow :update, as: :publish, when: token == "tok_hidden" or label == "shown"
      end

      expected_msg =
        "invalid predicate :token for allow :update, as: :publish in Hologram.Policy.ValidatorTest.InlinePolicyFixture36 - :token is server_only, and the client cannot decide :publish locally over a value it never holds. Server-only predicates are legal on allow :read only, which a client answers from the server's verdict on the row it was sent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture36], [])
      end
    end

    # The operand is read off the row too, so a server-only one is a value the client never holds.
    test "rejects a non-read predicate comparing with a server-only attribute" do
      defmodule InlinePolicyFixture39 do
        use Hologram.Entity

        attribute :label, :string
        attribute :token, :string, server_only: true

        allow :update, as: :publish, when: label == token
      end

      expected_msg =
        "invalid predicate :token for allow :update, as: :publish in Hologram.Policy.ValidatorTest.InlinePolicyFixture39 - :token is server_only, and the client cannot decide :publish locally over a value it never holds. Server-only predicates are legal on allow :read only, which a client answers from the server's verdict on the row it was sent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlinePolicyFixture39], [])
      end
    end

    test "rejects an invalid declaration of a given role module" do
      defmodule InvalidTargetRoleFixture1 do
        use Hologram.Role, extends: Module1
      end

      expected_msg =
        "invalid extends target Hologram.Test.Fixtures.Entity.Module1 in use Hologram.Role for Hologram.Policy.ValidatorTest.InvalidTargetRoleFixture1 - extends targets must be modules defined with use Hologram.Role"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module1], [InvalidTargetRoleFixture1])
      end
    end
  end

  describe "validate_model!/2 for named lines" do
    test "accepts one name on several lines of one operation" do
      defmodule NamedLinesFixture do
        use Hologram.Entity

        role :admin
        role :owner

        allow :update, as: :archive, to: :owner
        allow :update, as: :archive, to: :admin
      end

      assert validate_model!([NamedLinesFixture, Module14], []) == :ok
    end

    test "accepts one name on a bare grant lifecycle line and a per-role one" do
      defmodule NamedGrantLinesFixture do
        use Hologram.Entity

        role :editor
        role :owner

        allow :grant_role, as: :invite, to: :owner
        allow {:grant_role, :editor}, as: :invite, to: :editor
      end

      assert validate_model!([NamedGrantLinesFixture, Module14], []) == :ok
    end

    test "rejects one name on lines of two operations" do
      defmodule TwoOperationNameFixture do
        use Hologram.Entity

        allow :update, as: :archive
        allow :delete, as: :archive
      end

      expected_msg =
        "invalid as option :archive for allow :delete in Hologram.Policy.ValidatorTest.TwoOperationNameFixture - :archive already names allow :update in Hologram.Policy.ValidatorTest.TwoOperationNameFixture, and a name labels the lines of one operation"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TwoOperationNameFixture], [])
      end
    end

    test "rejects one name on grant_role and revoke_role lines" do
      defmodule GrantRevokeNameFixture do
        use Hologram.Entity

        role :owner

        allow :grant_role, as: :manage, to: :owner
        allow :revoke_role, as: :manage, to: :owner
      end

      expected_msg =
        "invalid as option :manage for allow :revoke_role in Hologram.Policy.ValidatorTest.GrantRevokeNameFixture - :manage already names allow :grant_role in Hologram.Policy.ValidatorTest.GrantRevokeNameFixture, and a name labels the lines of one operation"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([GrantRevokeNameFixture, Module14], [])
      end
    end

    test "names both policies a name on two operations comes from" do
      defmodule UpdateNamePolicy do
        use Hologram.Policy

        allow :update, as: :archive
      end

      defmodule DeleteNamePolicy do
        use Hologram.Policy

        allow :delete, as: :archive
      end

      defmodule TakenTwoOperationNameFixture do
        use Hologram.Entity

        policy Hologram.Policy.ValidatorTest.UpdateNamePolicy
        policy Hologram.Policy.ValidatorTest.DeleteNamePolicy
      end

      expected_msg =
        "invalid as option :archive for allow :delete in Hologram.Policy.ValidatorTest.TakenTwoOperationNameFixture, taken from Hologram.Policy.ValidatorTest.DeleteNamePolicy - :archive already names allow :update in Hologram.Policy.ValidatorTest.TakenTwoOperationNameFixture, taken from Hologram.Policy.ValidatorTest.UpdateNamePolicy, and a name labels the lines of one operation"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TakenTwoOperationNameFixture], [])
      end
    end

    # The server sends its verdict on a server-only condition under every key a line lands under,
    # a name included, so the browser answers can?(user, :peek, row) from it.
    test "accepts a named read line testing a server-only attribute" do
      defmodule NamedServerOnlyReadFixture do
        use Hologram.Entity

        attribute :secret, :boolean, default: false, server_only: true

        allow :read, when: secret == false
        allow :read, as: :peek, when: secret == true
      end

      assert validate_model!([NamedServerOnlyReadFixture], []) == :ok
    end

    # The line's chain sits under its name and under :update alike, and the name is reported
    # whatever it sorts as.
    test "describes a named line reading through a type nobody may read by its name" do
      defmodule LateNameChainTarget do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        allow :create
      end

      defmodule LateNameChainSource do
        use Hologram.Entity

        relationship :parent, Hologram.Policy.ValidatorTest.LateNameChainTarget

        allow :read
        allow :update, as: :zap, when: parent.archived == false
      end

      expected_msg =
        "allow :update, as: :zap in Hologram.Policy.ValidatorTest.LateNameChainSource reads Hologram.Policy.ValidatorTest.LateNameChainTarget through parent, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.LateNameChainTarget: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([LateNameChainTarget, LateNameChainSource], [])
      end
    end

    test "accepts a via option asking for a name the related entity type carries" do
      defmodule NamedDelegationTarget do
        use Hologram.Entity

        allow :read
        allow :update, as: :archive
      end

      defmodule NamedDelegationSource do
        use Hologram.Entity

        relationship :parent, Hologram.Policy.ValidatorTest.NamedDelegationTarget

        allow :read
        allow :update, via: {:archive, parent}
      end

      assert validate_model!([NamedDelegationTarget, NamedDelegationSource], []) == :ok
    end

    test "rejects a via cycle through a name" do
      defmodule NamedCycleEntityA do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.NamedCycleEntityB, optional: true

        allow :update, as: :archive, via: {:archive, peer}
      end

      defmodule NamedCycleEntityB do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.NamedCycleEntityA, optional: true

        allow :update, as: :archive, via: {:archive, peer}
      end

      expected_msg =
        normalize_newlines("""
        cyclic policy delegation for allow :update, as: :archive - a via chain can't return to the entity type it starts from:
          * Hologram.Policy.ValidatorTest.NamedCycleEntityA (via {:archive, :peer}) -> Hologram.Policy.ValidatorTest.NamedCycleEntityB (via {:archive, :peer}) -> Hologram.Policy.ValidatorTest.NamedCycleEntityA\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([NamedCycleEntityA, NamedCycleEntityB], [])
      end
    end

    # A browser decides a named read line through can?, so it holds the rows the line reads - which
    # the type's bare read rules, answered by the server's verdicts, never need.
    test "rejects a named read line reading through a type nobody may read" do
      defmodule NamedReadChainTarget do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        allow :create
      end

      defmodule NamedReadChainSource do
        use Hologram.Entity

        relationship :parent, Hologram.Policy.ValidatorTest.NamedReadChainTarget

        allow :read, as: :see, when: parent.archived == false
      end

      expected_msg =
        "allow :read, as: :see in Hologram.Policy.ValidatorTest.NamedReadChainSource reads Hologram.Policy.ValidatorTest.NamedReadChainTarget through parent, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.NamedReadChainTarget: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([NamedReadChainTarget, NamedReadChainSource], [])
      end
    end
  end

  describe "validate_model!/2 for field-limited lines" do
    test "accepts attributes and relationships, a to-one by its relationship name" do
      defmodule LimitedFieldsFixture do
        use Hologram.Entity

        attribute :topic, :string

        relationship :parent, Module1, optional: true
        relationship :tags, [Module2]

        allow :update, only: [:topic, :parent, :tags]
      end

      assert validate_model!([LimitedFieldsFixture], []) == :ok
    end

    test "rejects a to-one's reference field, naming the relationship" do
      defmodule ReferenceFieldFixture do
        use Hologram.Entity

        relationship :parent, Module1, optional: true

        allow :update, only: [:parent_id]
      end

      expected_msg =
        "invalid only option [:parent_id] for allow :update in Hologram.Policy.ValidatorTest.ReferenceFieldFixture - :parent_id is the reference field of relationship :parent - name the relationship: :parent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([ReferenceFieldFixture], [])
      end
    end

    test "names a named field-limited line by its name" do
      defmodule NamedUnknownFieldFixture do
        use Hologram.Entity

        relationship :tags, [Module2]

        allow :update, as: :retag, only: [:tagz]
      end

      expected_msg =
        "invalid only option [:tagz] for allow :update, as: :retag in Hologram.Policy.ValidatorTest.NamedUnknownFieldFixture - :tagz is no field of Hologram.Policy.ValidatorTest.NamedUnknownFieldFixture - the fields an update sets are :tags"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([NamedUnknownFieldFixture], [])
      end
    end

    test "rejects a to-many's name with _id as no field, not as a reference field" do
      defmodule ToManyIdFixture do
        use Hologram.Entity

        relationship :tags, [Module2]

        allow :update, only: [:tags_id]
      end

      expected_msg =
        "invalid only option [:tags_id] for allow :update in Hologram.Policy.ValidatorTest.ToManyIdFixture - :tags_id is no field of Hologram.Policy.ValidatorTest.ToManyIdFixture - the fields an update sets are :tags"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([ToManyIdFixture], [])
      end
    end

    test "rejects a job's framework-owned attribute" do
      defmodule FrameworkJobFieldFixture do
        use Hologram.Job

        attribute :reason, :string, optional: true

        allow :update, only: [:status]

        @impl Hologram.Job
        def run(_job), do: :ok
      end

      expected_msg =
        "invalid only option [:status] for allow :update in Hologram.Policy.ValidatorTest.FrameworkJobFieldFixture - :status is the framework's to set, so no only or except list names it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([FrameworkJobFieldFixture], [])
      end
    end

    test "rejects an inverse relationship" do
      defmodule InverseFieldChild do
        use Hologram.Entity

        relationship :parent, Hologram.Policy.ValidatorTest.InverseFieldParent, optional: true
      end

      defmodule InverseFieldParent do
        use Hologram.Entity

        relationship :children, [Hologram.Policy.ValidatorTest.InverseFieldChild], inverse: parent

        allow :update, only: [:children]
      end

      expected_msg =
        "invalid only option [:children] for allow :update in Hologram.Policy.ValidatorTest.InverseFieldParent - :children is an inverse relationship, which is written through the relationship it reverses"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InverseFieldChild, InverseFieldParent], [])
      end
    end

    test "rejects a derived field" do
      defmodule DerivedFieldFixture do
        use Hologram.Entity

        attribute :topic, :string

        derived :shout, :string, fn topic -> topic <> "!" end

        allow :update, except: [:shout]
      end

      expected_msg =
        "invalid except option [:shout] for allow :update in Hologram.Policy.ValidatorTest.DerivedFieldFixture - :shout is a derived field, which no update sets"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([DerivedFieldFixture], [])
      end
    end

    test "rejects a field the framework sets" do
      defmodule FrameworkFieldFixture do
        use Hologram.Entity

        attribute :topic, :string

        allow :update, only: [:created_at]
      end

      expected_msg =
        "invalid only option [:created_at] for allow :update in Hologram.Policy.ValidatorTest.FrameworkFieldFixture - :created_at is the framework's to set, so no only or except list names it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([FrameworkFieldFixture], [])
      end
    end

    test "rejects a field the entity type doesn't have, listing the ones it does" do
      defmodule UnknownFieldFixture do
        use Hologram.Entity

        attribute :name, :string
        attribute :topic, :string

        allow :update, only: [:topik]
      end

      expected_msg =
        "invalid only option [:topik] for allow :update in Hologram.Policy.ValidatorTest.UnknownFieldFixture - :topik is no field of Hologram.Policy.ValidatorTest.UnknownFieldFixture - the fields an update sets are :name, :topic"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([UnknownFieldFixture], [])
      end
    end

    test "rejects an except line leaving no field covered" do
      defmodule NothingLeftFixture do
        use Hologram.Entity

        attribute :topic, :string

        allow :update, except: [:topic]
      end

      expected_msg =
        "invalid except option [:topic] for allow :update in Hologram.Policy.ValidatorTest.NothingLeftFixture - it leaves no field of Hologram.Policy.ValidatorTest.NothingLeftFixture covered"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([NothingLeftFixture], [])
      end
    end

    # A's only update line is limited, so A's :update holds no rule and B's delegation to it ends
    # there - no cycle, though both lines delegate an update to each other.
    test "accepts a limited line delegating back to a type delegating to it" do
      defmodule LimitedCycleEntityA do
        use Hologram.Entity

        attribute :topic, :string, optional: true

        relationship :peer, Hologram.Policy.ValidatorTest.LimitedCycleEntityB, optional: true

        allow :read
        allow :update, only: [:topic], via: peer
      end

      defmodule LimitedCycleEntityB do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.LimitedCycleEntityA, optional: true

        allow :read
        allow :update, via: peer
      end

      assert validate_model!([LimitedCycleEntityA, LimitedCycleEntityB], []) == :ok
    end

    test "rejects a via cycle through a limited line's name" do
      defmodule LimitedNameCycleEntityA do
        use Hologram.Entity

        attribute :topic, :string, optional: true

        relationship :peer, Hologram.Policy.ValidatorTest.LimitedNameCycleEntityB, optional: true

        allow :update, as: :retitle, only: [:topic], via: {:retitle, peer}
      end

      defmodule LimitedNameCycleEntityB do
        use Hologram.Entity

        attribute :topic, :string, optional: true

        relationship :peer, Hologram.Policy.ValidatorTest.LimitedNameCycleEntityA, optional: true

        allow :update, as: :retitle, only: [:topic], via: {:retitle, peer}
      end

      expected_msg =
        normalize_newlines("""
        cyclic policy delegation for allow :update, as: :retitle - a via chain can't return to the entity type it starts from:
          * Hologram.Policy.ValidatorTest.LimitedNameCycleEntityA (via {:retitle, :peer}) -> Hologram.Policy.ValidatorTest.LimitedNameCycleEntityB (via {:retitle, :peer}) -> Hologram.Policy.ValidatorTest.LimitedNameCycleEntityA\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([LimitedNameCycleEntityA, LimitedNameCycleEntityB], [])
      end
    end

    test "describes an except line reading through a type nobody may read as it was written" do
      defmodule ExceptChainTarget do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        allow :create
      end

      defmodule ExceptChainSource do
        use Hologram.Entity

        attribute :topic, :string

        relationship :parent, Hologram.Policy.ValidatorTest.ExceptChainTarget

        allow :read
        allow :update, except: [:parent], when: parent.archived == false
      end

      expected_msg =
        "allow :update, except: [:parent] in Hologram.Policy.ValidatorTest.ExceptChainSource reads Hologram.Policy.ValidatorTest.ExceptChainTarget through parent, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.ExceptChainTarget: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([ExceptChainTarget, ExceptChainSource], [])
      end
    end

    test "describes a limited line reading through a type nobody may read as it was written" do
      defmodule LimitedChainTarget do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        allow :create
      end

      defmodule LimitedChainSource do
        use Hologram.Entity

        attribute :topic, :string

        relationship :parent, Hologram.Policy.ValidatorTest.LimitedChainTarget

        allow :read
        allow :update, only: [:topic], when: parent.archived == false
      end

      expected_msg =
        "allow :update, only: [:topic] in Hologram.Policy.ValidatorTest.LimitedChainSource reads Hologram.Policy.ValidatorTest.LimitedChainTarget through parent, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.LimitedChainTarget: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([LimitedChainTarget, LimitedChainSource], [])
      end
    end
  end

  # Every message below has a local-line twin in the describe above, asserting the same text
  # WITHOUT the tail - so the pair pins that the tail appears exactly when the line was taken.
  describe "validate_model!/2 for a line taken from a policy" do
    test "rejects a field-limited line naming user_id() without a user entity designation" do
      defmodule TakenActorLimitedPolicy do
        use Hologram.Policy

        allow :update, only: [:title], when: author_id == user_id()
      end

      defmodule TakenActorLimitedEntity do
        use Hologram.Entity

        attribute :author_id, :uuid
        attribute :title, :string

        policy TakenActorLimitedPolicy
      end

      expected_msg =
        "invalid predicate for allow :update, only: [:title] in Hologram.Policy.ValidatorTest.TakenActorLimitedEntity, taken from Hologram.Policy.ValidatorTest.TakenActorLimitedPolicy - it names user_id(), but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TakenActorLimitedEntity], [])
      end
    end

    test "names the line reading the chain among the limited lines covering a field" do
      defmodule SharedFieldChainTarget do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        allow :create
      end

      defmodule SharedFieldChainSource do
        use Hologram.Entity

        attribute :topic, :string

        relationship :parent, Hologram.Policy.ValidatorTest.SharedFieldChainTarget

        allow :read
        allow :update, only: [:topic]
        allow :update, except: [:parent], when: parent.archived == false
      end

      expected_msg =
        "allow :update, except: [:parent] in Hologram.Policy.ValidatorTest.SharedFieldChainSource reads Hologram.Policy.ValidatorTest.SharedFieldChainTarget through parent, which declares no allow :read line - no browser ever holds such a row, so a check on a new or changed struct answers no in every browser while the server may answer yes. Declare an allow :read line on Hologram.Policy.ValidatorTest.SharedFieldChainTarget: a browser holding the row answers such a check itself"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([SharedFieldChainTarget, SharedFieldChainSource], [])
      end
    end

    test "rejects a to option naming a role the taking entity type does not declare" do
      defmodule TakenOwnReferencePolicy do
        use Hologram.Policy

        allow :update, to: :publisher
      end

      defmodule TakenOwnReferenceEntity do
        use Hologram.Entity

        role :editor

        policy TakenOwnReferencePolicy
      end

      expected_msg =
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.ValidatorTest.TakenOwnReferenceEntity, taken from Hologram.Policy.ValidatorTest.TakenOwnReferencePolicy - declared roles are: :editor"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenOwnReferenceEntity], [])
      end
    end

    test "rejects a to option referencing a non-entity module" do
      defmodule TakenTypeReferencePolicy do
        use Hologram.Policy

        allow :update, to: {:editor, Hologram.Reflection}
      end

      defmodule TakenTypeReferenceEntity do
        use Hologram.Entity

        policy TakenTypeReferencePolicy
      end

      expected_msg =
        "invalid to option {:editor, Hologram.Reflection} for allow :update in Hologram.Policy.ValidatorTest.TakenTypeReferenceEntity, taken from Hologram.Policy.ValidatorTest.TakenTypeReferencePolicy - Hologram.Reflection is not an entity type module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenTypeReferenceEntity], [])
      end
    end

    test "rejects a to option referencing an undeclared role of another entity type" do
      defmodule TakenTargetRolePolicy do
        use Hologram.Policy

        allow :update, to: {:publisher, Hologram.Test.Fixtures.Entity.Module13}
      end

      defmodule TakenTargetRoleEntity do
        use Hologram.Entity

        policy TakenTargetRolePolicy
      end

      expected_msg =
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.ValidatorTest.TakenTargetRoleEntity, taken from Hologram.Policy.ValidatorTest.TakenTargetRolePolicy - declared roles of Hologram.Test.Fixtures.Entity.Module13 are: :editor, :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenTargetRoleEntity], [])
      end
    end

    test "rejects a to option naming a relationship the taking entity type does not declare" do
      defmodule TakenUnknownRelationshipPolicy do
        use Hologram.Policy

        allow :update, to: {:editor, project}
      end

      defmodule TakenUnknownRelationshipEntity do
        use Hologram.Entity

        relationship :parent, Module13

        policy TakenUnknownRelationshipPolicy
      end

      expected_msg =
        "unknown relationship :project in the to option of allow :update in Hologram.Policy.ValidatorTest.TakenUnknownRelationshipEntity, taken from Hologram.Policy.ValidatorTest.TakenUnknownRelationshipPolicy - declared relationships are: :parent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenUnknownRelationshipEntity], [])
      end
    end

    test "rejects a to option referencing a role on a to-many relationship" do
      defmodule TakenToManyPolicy do
        use Hologram.Policy

        allow :update, to: {:editor, children}
      end

      defmodule TakenToManyEntity do
        use Hologram.Entity

        relationship :children, [Module13]

        policy TakenToManyPolicy
      end

      expected_msg =
        "invalid to option {:editor, :children} for allow :update in Hologram.Policy.ValidatorTest.TakenToManyEntity, taken from Hologram.Policy.ValidatorTest.TakenToManyPolicy - relationship :children is to-many, but a role reference requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenToManyEntity], [])
      end
    end

    test "rejects a to option naming a module that is not a role module" do
      defmodule TakenGlobalReferencePolicy do
        use Hologram.Policy

        allow :update, to: Hologram.Reflection
      end

      defmodule TakenGlobalReferenceEntity do
        use Hologram.Entity

        policy TakenGlobalReferencePolicy
      end

      expected_msg =
        "invalid to option Hologram.Reflection for allow :update in Hologram.Policy.ValidatorTest.TakenGlobalReferenceEntity, taken from Hologram.Policy.ValidatorTest.TakenGlobalReferencePolicy - Hologram.Reflection is not a role module (define it with use Hologram.Role)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenGlobalReferenceEntity], [])
      end
    end

    test "names the innermost policy for a line taken through two hops" do
      defmodule TakenInnerPolicy do
        use Hologram.Policy

        allow :update, to: :publisher
      end

      defmodule TakenOuterPolicy do
        use Hologram.Policy

        policy TakenInnerPolicy
      end

      defmodule TakenTwoHopsEntity do
        use Hologram.Entity

        role :editor

        policy TakenOuterPolicy
      end

      expected_msg =
        "unknown role :publisher in the to option of allow :update in Hologram.Policy.ValidatorTest.TakenTwoHopsEntity, taken from Hologram.Policy.ValidatorTest.TakenInnerPolicy - declared roles are: :editor"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenTwoHopsEntity], [])
      end
    end

    test "rejects a via option naming a relationship the taking entity type does not declare" do
      defmodule TakenUnknownViaPolicy do
        use Hologram.Policy

        allow :read, via: project
      end

      defmodule TakenUnknownViaEntity do
        use Hologram.Entity

        relationship :parent, Module13

        policy TakenUnknownViaPolicy
      end

      expected_msg =
        "unknown relationship :project in the via option of allow :read in Hologram.Policy.ValidatorTest.TakenUnknownViaEntity, taken from Hologram.Policy.ValidatorTest.TakenUnknownViaPolicy - declared relationships are: :parent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TakenUnknownViaEntity], [])
      end
    end

    test "rejects a via option naming a to-many relationship" do
      defmodule TakenToManyViaPolicy do
        use Hologram.Policy

        allow :read, via: children
      end

      defmodule TakenToManyViaEntity do
        use Hologram.Entity

        relationship :children, [Module13]

        policy TakenToManyViaPolicy
      end

      expected_msg =
        "invalid via option :children for allow :read in Hologram.Policy.ValidatorTest.TakenToManyViaEntity, taken from Hologram.Policy.ValidatorTest.TakenToManyViaPolicy - relationship :children is to-many, but delegation requires a to-one relationship"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TakenToManyViaEntity], [])
      end
    end

    test "rejects a via option that is not a relationship name" do
      defmodule TakenNonAtomViaPolicy do
        use Hologram.Policy

        allow :read, via: ^"parent"
      end

      defmodule TakenNonAtomViaEntity do
        use Hologram.Entity

        relationship :parent, Module13

        policy TakenNonAtomViaPolicy
      end

      expected_msg =
        "invalid via option \"parent\" for allow :read in Hologram.Policy.ValidatorTest.TakenNonAtomViaEntity, taken from Hologram.Policy.ValidatorTest.TakenNonAtomViaPolicy - the via option must be a relationship name, a path, or an {operation, relationship} tuple"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TakenNonAtomViaEntity], [])
      end
    end

    test "rejects a via option naming an operation the related entity type can't be asked about" do
      defmodule TakenUnaskableViaPolicy do
        use Hologram.Policy

        allow :update, as: :publish, via: {:publish, parent}
      end

      defmodule TakenUnaskableViaEntity do
        use Hologram.Entity

        relationship :parent, Module1

        policy TakenUnaskableViaPolicy
      end

      expected_msg =
        "invalid via option {:publish, :parent} for allow :update, as: :publish in Hologram.Policy.ValidatorTest.TakenUnaskableViaEntity, taken from Hologram.Policy.ValidatorTest.TakenUnaskableViaPolicy - unknown operation :publish for Hologram.Test.Fixtures.Entity.Module1 - the framework's operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update, and its allow lines carry no name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TakenUnaskableViaEntity], [])
      end
    end

    test "rejects a predicate naming an attribute the taking entity type does not declare" do
      defmodule TakenUnknownPredicatePolicy do
        use Hologram.Policy

        allow :read, when: published == true
      end

      defmodule TakenUnknownPredicateEntity do
        use Hologram.Entity

        attribute :title, :string

        policy TakenUnknownPredicatePolicy
      end

      expected_msg =
        "invalid predicate for allow :read in Hologram.Policy.ValidatorTest.TakenUnknownPredicateEntity, taken from Hologram.Policy.ValidatorTest.TakenUnknownPredicatePolicy - unknown attribute :published in Hologram.Policy.ValidatorTest.TakenUnknownPredicateEntity - known attributes: :created_at, :id, :server_created_at, :server_updated_at, :title, :updated_at"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TakenUnknownPredicateEntity], [])
      end
    end

    test "rejects a non-read predicate over a server-only attribute" do
      defmodule TakenServerOnlyPolicy do
        use Hologram.Policy

        allow :update, as: :publish, when: token == "tok_hidden"
      end

      defmodule TakenServerOnlyEntity do
        use Hologram.Entity

        attribute :token, :string, server_only: true

        policy TakenServerOnlyPolicy
      end

      expected_msg =
        "invalid predicate :token for allow :update, as: :publish in Hologram.Policy.ValidatorTest.TakenServerOnlyEntity, taken from Hologram.Policy.ValidatorTest.TakenServerOnlyPolicy - :token is server_only, and the client cannot decide :publish locally over a value it never holds. Server-only predicates are legal on allow :read only, which a client answers from the server's verdict on the row it was sent"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TakenServerOnlyEntity], [])
      end
    end

    test "rejects a gate reference the gate cannot honor" do
      defmodule TakenRelationshipGatePolicy do
        use Hologram.Policy

        allow :grant_role, to: {:admin, parent}
      end

      defmodule TakenRelationshipGateEntity do
        use Hologram.Entity

        relationship :parent, Hologram.Test.Fixtures.Policy.Module2, optional: true

        policy TakenRelationshipGatePolicy
      end

      expected_msg =
        "invalid to option {:admin, :parent} for allow :grant_role in Hologram.Policy.ValidatorTest.TakenRelationshipGateEntity, taken from Hologram.Policy.ValidatorTest.TakenRelationshipGatePolicy - :grant_role is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenRelationshipGateEntity], [])
      end
    end

    test "rejects a gate predicate the gate cannot honor" do
      defmodule TakenPredicateGatePolicy do
        use Hologram.Policy

        allow :grant_role, to: :owner, when: archived == false
      end

      defmodule TakenPredicateGateEntity do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        role :owner

        policy TakenPredicateGatePolicy
      end

      expected_msg =
        "invalid predicate :archived for allow :grant_role in Hologram.Policy.ValidatorTest.TakenPredicateGateEntity, taken from Hologram.Policy.ValidatorTest.TakenPredicateGatePolicy - :grant_role is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenPredicateGateEntity], [])
      end
    end

    test "rejects a gate delegation the gate cannot honor" do
      defmodule TakenDelegatedGatePolicy do
        use Hologram.Policy

        allow :read_roles, via: parent
      end

      defmodule TakenDelegatedGateEntity do
        use Hologram.Entity

        relationship :parent, Hologram.Test.Fixtures.Policy.Module2, optional: true

        policy TakenDelegatedGatePolicy
      end

      expected_msg =
        "invalid via option :parent for allow :read_roles in Hologram.Policy.ValidatorTest.TakenDelegatedGateEntity, taken from Hologram.Policy.ValidatorTest.TakenDelegatedGatePolicy - :read_roles is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenDelegatedGateEntity], [])
      end
    end

    test "annotates every hop of a delegation cycle no single entity type declares" do
      defmodule TakenViaCyclePolicy do
        use Hologram.Policy

        allow :read, via: peer
      end

      defmodule TakenViaCycleEntityA do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.TakenViaCycleEntityB, optional: true

        policy TakenViaCyclePolicy
      end

      defmodule TakenViaCycleEntityB do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.TakenViaCycleEntityA, optional: true

        policy TakenViaCyclePolicy
      end

      expected_msg =
        normalize_newlines("""
        cyclic policy delegation for allow :read - a via chain can't return to the entity type it starts from:
          * Hologram.Policy.ValidatorTest.TakenViaCycleEntityA (via :peer, from Hologram.Policy.ValidatorTest.TakenViaCyclePolicy) -> Hologram.Policy.ValidatorTest.TakenViaCycleEntityB (via :peer, from Hologram.Policy.ValidatorTest.TakenViaCyclePolicy) -> Hologram.Policy.ValidatorTest.TakenViaCycleEntityA\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([TakenViaCycleEntityA, TakenViaCycleEntityB], [])
      end
    end

    test "leaves a delegation hop the entity type declared itself unannotated" do
      defmodule MixedViaCyclePolicy do
        use Hologram.Policy

        allow :update, as: :publish, via: {:publish, peer}
      end

      defmodule MixedViaCycleEntityA do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.MixedViaCycleEntityB, optional: true

        policy MixedViaCyclePolicy
      end

      defmodule MixedViaCycleEntityB do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.ValidatorTest.MixedViaCycleEntityA, optional: true

        allow :update, as: :publish, via: {:publish, peer}
      end

      expected_msg =
        normalize_newlines("""
        cyclic policy delegation for allow :update, as: :publish - a via chain can't return to the entity type it starts from:
          * Hologram.Policy.ValidatorTest.MixedViaCycleEntityA (via {:publish, :peer}, from Hologram.Policy.ValidatorTest.MixedViaCyclePolicy) -> Hologram.Policy.ValidatorTest.MixedViaCycleEntityB (via {:publish, :peer}) -> Hologram.Policy.ValidatorTest.MixedViaCycleEntityA\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([MixedViaCycleEntityA, MixedViaCycleEntityB], [])
      end
    end

    test "rejects a gate line naming no own role" do
      defmodule TakenUnqualifiedGatePolicy do
        use Hologram.Policy

        allow :grant_role
      end

      defmodule TakenUnqualifiedGateEntity do
        use Hologram.Entity

        role :owner

        policy TakenUnqualifiedGatePolicy
      end

      expected_msg =
        "missing to option for allow :grant_role in Hologram.Policy.ValidatorTest.TakenUnqualifiedGateEntity, taken from Hologram.Policy.ValidatorTest.TakenUnqualifiedGatePolicy - :grant_role is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, TakenUnqualifiedGateEntity], [])
      end
    end
  end

  describe "validate_model!/2 for the grant lifecycle operations" do
    test "accepts a tuple naming a declared role" do
      defmodule RoleTupleGateFixture do
        use Hologram.Entity

        role :editor
        role :viewer

        allow {:grant_role, :viewer}, to: :editor
      end

      assert validate_model!([Module14, RoleTupleGateFixture], []) == :ok
    end

    test "accepts a tuple naming several declared roles" do
      defmodule RoleListGateFixture do
        use Hologram.Entity

        role :editor
        role :viewer

        allow {:revoke_role, [:viewer, :editor]}, to: :editor
      end

      assert validate_model!([Module14, RoleListGateFixture], []) == :ok
    end

    test "returns :ok for own role references" do
      defmodule OwnGateFixture do
        use Hologram.Entity

        role :editor
        role :owner

        allow :grant_role, to: [:editor, :owner]
        allow :read_roles, to: :owner
        allow :revoke_role, to: :owner
      end

      assert validate_model!([Module14, OwnGateFixture], []) == :ok
    end

    test "accepts a global role module as a holder" do
      defmodule GlobalHolderGateFixture do
        use Hologram.Entity

        role :owner

        allow :grant_role, to: [:owner, Hologram.Test.Fixtures.Role.Module1]
      end

      assert validate_model!([Module14, GlobalHolderGateFixture], []) == :ok
    end

    test "accepts a global role module as the holder of a per-role line" do
      defmodule GlobalHolderRoleTupleGateFixture do
        use Hologram.Entity

        role :viewer

        allow {:grant_role, :viewer}, to: Hologram.Test.Fixtures.Role.Module1
      end

      assert validate_model!([Module14, GlobalHolderRoleTupleGateFixture], []) == :ok
    end

    test "rejects a reference the gate cannot honor" do
      defmodule RelationshipGateFixture do
        use Hologram.Entity

        relationship :parent, Hologram.Test.Fixtures.Policy.Module2, optional: true

        allow :grant_role, to: {:admin, parent}
      end

      expected_msg =
        "invalid to option {:admin, :parent} for allow :grant_role in Hologram.Policy.ValidatorTest.RelationshipGateFixture - :grant_role is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, RelationshipGateFixture], [])
      end
    end

    test "rejects a reference through a path the gate cannot honor" do
      defmodule PathRelationshipGateFixture do
        use Hologram.Entity

        relationship :parent, Hologram.Test.Fixtures.Policy.Module5, optional: true

        allow :grant_role, to: {:viewer, parent.parent}
      end

      expected_msg =
        "invalid to option {:viewer, parent.parent} for allow :grant_role in Hologram.Policy.ValidatorTest.PathRelationshipGateFixture - :grant_role is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, PathRelationshipGateFixture], [])
      end
    end

    test "rejects a predicate the gate cannot honor" do
      defmodule PredicateGateFixture do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        role :owner

        allow :revoke_role, to: :owner, when: archived == false
      end

      expected_msg =
        "invalid predicate :archived for allow :revoke_role in Hologram.Policy.ValidatorTest.PredicateGateFixture - :revoke_role is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, PredicateGateFixture], [])
      end
    end

    # The line's condition names two attributes and or names none, so the refusal names the first.
    test "rejects a predicate inside a disjunction the gate cannot honor" do
      defmodule DisjunctionGateFixture do
        use Hologram.Entity

        attribute :archived, :boolean, default: false
        attribute :pinned, :boolean, default: false

        role :owner

        allow :grant_role, to: :owner, when: archived == false or pinned == true
      end

      expected_msg =
        "invalid predicate :archived for allow :grant_role in Hologram.Policy.ValidatorTest.DisjunctionGateFixture - :grant_role is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, DisjunctionGateFixture], [])
      end
    end

    test "rejects a predicate through a path the gate cannot honor" do
      defmodule PathGateFixture do
        use Hologram.Entity

        relationship :parent, Module13

        role :owner

        allow :grant_role, to: :owner, when: parent.public == true
      end

      expected_msg =
        "invalid predicate parent.public for allow :grant_role in Hologram.Policy.ValidatorTest.PathGateFixture - :grant_role is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, PathGateFixture], [])
      end
    end

    test "rejects a line naming no own role" do
      defmodule UnqualifiedGateFixture do
        use Hologram.Entity

        role :owner

        allow :grant_role
      end

      expected_msg =
        "missing to option for allow :grant_role in Hologram.Policy.ValidatorTest.UnqualifiedGateFixture - :grant_role is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, UnqualifiedGateFixture], [])
      end
    end

    test "rejects a delegation the gate cannot honor" do
      defmodule DelegatedGateFixture do
        use Hologram.Entity

        relationship :parent, Hologram.Test.Fixtures.Policy.Module2, optional: true

        allow :read_roles, via: parent
      end

      expected_msg =
        "invalid via option :parent for allow :read_roles in Hologram.Policy.ValidatorTest.DelegatedGateFixture - :read_roles is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, DelegatedGateFixture], [])
      end
    end

    test "rejects a delegation through a path the gate cannot honor" do
      defmodule PathDelegatedGateFixture do
        use Hologram.Entity

        relationship :parent, Hologram.Test.Fixtures.Policy.Module5, optional: true

        allow :read_roles, via: {:read, parent.parent}
      end

      expected_msg =
        "invalid via option {:read, parent.parent} for allow :read_roles in Hologram.Policy.ValidatorTest.PathDelegatedGateFixture - :read_roles is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, PathDelegatedGateFixture], [])
      end
    end

    test "names a named per-role line as written" do
      defmodule NamedUndeclaredRoleGateFixture do
        use Hologram.Entity

        role :editor
        role :owner

        allow {:grant_role, :editr}, as: :invite, to: :owner
      end

      expected_msg =
        "unknown role :editr in allow {:grant_role, :editr}, as: :invite in Hologram.Policy.ValidatorTest.NamedUndeclaredRoleGateFixture - declared roles are: :editor, :owner"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, NamedUndeclaredRoleGateFixture], [])
      end
    end

    test "rejects a tuple naming an undeclared role" do
      defmodule UndeclaredRoleTupleGateFixture do
        use Hologram.Entity

        role :editor
        role :viewer

        allow {:grant_role, [:viewer, :admin]}, to: :editor
      end

      expected_msg =
        "unknown role :admin in allow {:grant_role, [:viewer, :admin]} in Hologram.Policy.ValidatorTest.UndeclaredRoleTupleGateFixture - declared roles are: :editor, :viewer"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, UndeclaredRoleTupleGateFixture], [])
      end
    end

    # The gate refusal says what is wrong with the line - asked first, the related type would be
    # judged on a role it never declares.
    test "rejects a tuple with a delegation" do
      defmodule DelegatingRoleTupleGateFixture do
        use Hologram.Entity

        relationship :parent, Module1

        role :editor
        role :viewer

        allow {:grant_role, :viewer}, to: :editor, via: parent
      end

      expected_msg =
        "invalid via option :parent for allow {:grant_role, :viewer} in Hologram.Policy.ValidatorTest.DelegatingRoleTupleGateFixture - {:grant_role, :viewer} is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, DelegatingRoleTupleGateFixture], [])
      end
    end

    test "rejects a tuple with a predicate" do
      defmodule PredicateRoleTupleGateFixture do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        role :editor
        role :viewer

        allow {:grant_role, :viewer}, to: :editor, when: archived == false
      end

      expected_msg =
        "invalid predicate :archived for allow {:grant_role, :viewer} in Hologram.Policy.ValidatorTest.PredicateRoleTupleGateFixture - {:grant_role, :viewer} is checked without loading the row, so it takes own role names and global role modules only"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, PredicateRoleTupleGateFixture], [])
      end
    end
  end

  describe "validate_model!/2 with global role references" do
    test "returns :ok for a declared role module reference" do
      defmodule ValidGlobalReferenceFixture do
        use Hologram.Entity

        allow :read, to: Hologram.Test.Fixtures.Role.Module1
      end

      assert validate_model!([Module14, ValidGlobalReferenceFixture], []) == :ok
    end

    test "rejects a to option naming a module that is not a role" do
      defmodule InvalidGlobalReferenceFixture do
        use Hologram.Entity

        allow :read, to: Hologram.Test.Fixtures.Entity.Module1
      end

      expected_msg =
        "invalid to option Hologram.Test.Fixtures.Entity.Module1 for allow :read in Hologram.Policy.ValidatorTest.InvalidGlobalReferenceFixture - Hologram.Test.Fixtures.Entity.Module1 is not a role module (define it with use Hologram.Role)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([Module14, InvalidGlobalReferenceFixture], [])
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
        "invalid extends target Hologram.Test.Fixtures.Entity.Module1 in use Hologram.Role for Hologram.Policy.ValidatorTest.InvalidTargetRoleFixture - extends targets must be modules defined with use Hologram.Role"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_role_modules!([InvalidTargetRoleFixture])
      end
    end

    test "rejects an extension cycle" do
      defmodule CyclicRoleFixture1 do
        use Hologram.Role, extends: Hologram.Policy.ValidatorTest.CyclicRoleFixture2
      end

      defmodule CyclicRoleFixture2 do
        use Hologram.Role, extends: Hologram.Policy.ValidatorTest.CyclicRoleFixture1
      end

      expected_msg =
        normalize_newlines("""
        cyclic role extension - an extends chain can't return to the role it starts from:
          * Hologram.Policy.ValidatorTest.CyclicRoleFixture1 -> Hologram.Policy.ValidatorTest.CyclicRoleFixture2 -> Hologram.Policy.ValidatorTest.CyclicRoleFixture1\
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
        "role module name Hologram.Policy.ValidatorTest.ThisIsAVeryLongRoleModuleNameUsedToExceedThePostgresEnumLabelLimit is too long to store as a grant value (96 bytes, limit 63) - shorten the module name"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_role_modules!([
          ThisIsAVeryLongRoleModuleNameUsedToExceedThePostgresEnumLabelLimit
        ])
      end
    end
  end
end
