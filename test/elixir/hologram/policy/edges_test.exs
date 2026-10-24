defmodule Hologram.Policy.EdgesTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy.Edges

  alias Hologram.Auth.RoleGrant
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy
  alias Hologram.Test.Fixtures.Role

  describe "derive/1" do
    test "derives the full edge list per operation for a policy-declaring model" do
      assert derive([Policy.Module1]) == %{
               {Policy.Module1, :archive} => [{:attributes, [:author_id]}],
               {Policy.Module1, :delete} => [
                 {:attributes, [:parent_id]},
                 {:relationship_grants, [:parent], Policy.Module2, [:admin]}
               ],
               {Policy.Module1, :grant_role} => [{:own_grants, [:owner]}],
               {Policy.Module1, {:grant_role, :editor}} => [{:own_grants, [:owner]}],
               {Policy.Module1, {:grant_role, :owner}} => [{:own_grants, [:owner]}],
               {Policy.Module1, :publish} => [
                 {:attributes, [:parent_id]},
                 {:relationship_attributes, [:parent], Policy.Module2, [:public]}
               ],
               {Policy.Module1, :read} => [
                 {:attributes, [:public]},
                 {:own_grants, [:viewer]},
                 {:type_grants, Policy.Module2, [:admin]}
               ],
               {Policy.Module1, :revoke_role} => [{:own_grants, [:owner]}],
               {Policy.Module1, {:revoke_role, :editor}} => [{:own_grants, [:owner]}],
               {Policy.Module1, {:revoke_role, :owner}} => [{:own_grants, [:owner]}],
               {Policy.Module1, :update} => [
                 {:attributes, [:priority]},
                 {:own_grants, [:editor, :owner]}
               ]
             }
    end

    test "derives a global-grant edge for a per-role gate rule with a global holder" do
      defmodule GlobalHolderGateFixture do
        use Hologram.Entity

        role :viewer

        allow :grant_role, to: Hologram.Test.Fixtures.Role.Module1
      end

      edges = derive([GlobalHolderGateFixture])

      assert edges[{GlobalHolderGateFixture, {:grant_role, :viewer}}] == [
               {:global_grants, [Role.Module1, Role.Module2]}
             ]
    end

    test "derives a global-grant edge for a referenced role module" do
      edges = derive([Policy.Module2])

      assert edges[{Policy.Module2, :archive}] == [
               {:global_grants, [Role.Module1, Role.Module2]}
             ]
    end

    test "derives a self-attribute edge for an actor-comparing predicate" do
      assert derive([Module14]) == %{{Module14, :read} => [{:attributes, [:id]}]}
    end

    test "derives resource-grant edges for the grant store" do
      assert derive([RoleGrant]) == %{
               {RoleGrant, :read} => [
                 {:attributes, [:entity_type, :user_id]},
                 {:global_grants, [Role.Module1, Role.Module2]},
                 {:named_grants, Policy.Module1, [:owner]},
                 {:named_grants, Policy.Module2, [:admin, :member]}
               ]
             }
    end

    test "expands delegation chains transitively" do
      defmodule ChainFixture3 do
        use Hologram.Entity

        attribute :approved, :boolean, default: false

        role :moderator

        allow :publish, to: :moderator, when: approved == true
      end

      defmodule ChainFixture2 do
        use Hologram.Entity

        relationship :c, ChainFixture3

        allow :publish, via: c
      end

      defmodule ChainFixture1 do
        use Hologram.Entity

        relationship :b, ChainFixture2

        allow :publish, via: b
      end

      assert derive([ChainFixture1]) == %{
               {ChainFixture1, :publish} => [
                 {:attributes, [:b_id]},
                 {:relationship_attributes, [:b], ChainFixture2, [:c_id]},
                 {:relationship_attributes, [:b, :c], ChainFixture3, [:approved]},
                 {:relationship_grants, [:b, :c], ChainFixture3, [:moderator]}
               ]
             }
    end

    # The create asks the related row's update, so its edges are the update rule's, lifted one hop -
    # the related type's create rule is open and reads nothing.
    test "lifts the related type's edges for the operation a delegation names" do
      assert derive([Policy.Module11]) == %{
               {Policy.Module11, :create} => [
                 {:attributes, [:parent_id]},
                 {:relationship_attributes, [:parent], Policy.Module10, [:archived]},
                 {:relationship_grants, [:parent], Policy.Module10, [:editor]}
               ]
             }
    end

    # A disjunction reads the row's own attributes, so its alternatives' attributes join the rule's
    # one attribute edge rather than adding a kind of edge.
    test "derives one attribute edge for a condition holding a disjunction" do
      defmodule DisjunctionFixture do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module14

        attribute :shared, :boolean, default: false

        relationship :author, Module14, optional: true

        allow :read, when: author_id == user_id() or shared == true
      end

      assert derive([DisjunctionFixture]) == %{
               {DisjunctionFixture, :read} => [{:attributes, [:author_id, :shared]}]
             }
    end

    # A comparison between two attributes reads both off the row, so both join the rule's one
    # attribute edge rather than adding a kind of edge.
    test "derives one attribute edge naming both sides of an attribute comparison" do
      defmodule AttributeComparisonFixture do
        use Hologram.Entity

        attribute :capacity, :integer
        attribute :guests, :integer

        allow :update, when: guests <= capacity
      end

      assert derive([AttributeComparisonFixture]) == %{
               {AttributeComparisonFixture, :update} => [{:attributes, [:capacity, :guests]}]
             }
    end

    test "derives no pairs for an entity type without policy declarations" do
      assert derive([Module1]) == %{}
    end
  end

  describe "universal_edges/0" do
    test "names the session-wide invalidation kinds" do
      assert universal_edges() == [:auth_change, :deploy]
    end
  end
end
