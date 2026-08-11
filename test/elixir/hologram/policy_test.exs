defmodule Hologram.PolicyTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Policy.Compiler
  alias Hologram.Test.Fixtures.Role

  describe "allow/2" do
    test "replays declarations into the including entity type in declaration order" do
      defmodule AllowPolicyFixture do
        use Hologram.Policy

        allow :read
        allow :update, to: :editor
      end

      defmodule AllowEntityFixture do
        use Hologram.Entity
        use AllowPolicyFixture

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
        use ActorPolicyFixture
      end

      assert Compiler.build(ActorEntityFixture)[:archive] == [
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
        use GlobalReferencePolicyFixture
      end

      assert Compiler.build(GlobalReferenceEntityFixture)[:read] == [
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
        use DuplicateLinePolicyFixture1
        use DuplicateLinePolicyFixture2
      end

      assert DuplicateLineEntityFixture.__policies__() == [
               {:read, nil, nil, []},
               {:read, nil, nil, []}
             ]
    end

    test "raises at the policy module's own compile for an invalid declaration" do
      expected_msg =
        "invalid operation 123 used for allow in Hologram.PolicyTest.InvalidAllowPolicyFixture - policy operations must be atoms"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InvalidAllowPolicyFixture do
          use Hologram.Policy

          allow 123
        end
      end
    end
  end

  describe "role/2" do
    test "replays a role declaration into the including entity type" do
      defmodule RolePolicyFixture do
        use Hologram.Policy

        role :moderator, creator: true
      end

      defmodule RoleEntityFixture do
        use Hologram.Entity
        use RolePolicyFixture

        role :owner
      end

      assert RoleEntityFixture.__roles__() == [{:moderator, [creator: true]}, {:owner, []}]
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
        use DuplicateRolePolicyFixture1
        use DuplicateRolePolicyFixture2
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

  describe "use" do
    test "replays the declarations of a nested policy before the outer ones" do
      defmodule NestedInnerPolicyFixture do
        use Hologram.Policy

        role :viewer

        allow :read, to: :viewer
      end

      defmodule NestedOuterPolicyFixture do
        use Hologram.Policy
        use NestedInnerPolicyFixture

        allow :update, to: :viewer
      end

      defmodule NestedEntityFixture do
        use Hologram.Entity
        use NestedOuterPolicyFixture
      end

      assert NestedEntityFixture.__roles__() == [{:viewer, []}]

      assert NestedEntityFixture.__policies__() == [
               {:read, :viewer, nil, []},
               {:update, :viewer, nil, []}
             ]
    end

    test "raises in a module that is neither an entity type nor a policy" do
      defmodule TargetPolicyFixture do
        use Hologram.Policy

        allow :read
      end

      expected_msg =
        "policies can be used only in a module with use Hologram.Entity or use Hologram.Policy - Hologram.PolicyTest.PlainModuleFixture has neither"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule PlainModuleFixture do
          use TargetPolicyFixture
        end
      end
    end
  end
end
