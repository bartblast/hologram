defmodule Hologram.Policy.EdgesTest do
  # async: false - the index cache is one persistent term for the whole node, and proving it is
  # READ means standing a value in it that is not the real index. Every concurrent read of the index
  # would see that value while it stands.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Policy.Edges

  alias Hologram.Auth.RoleGrant
  alias Hologram.Entity.Model
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module17
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module41
  alias Hologram.Test.Fixtures.Entity.Module42
  alias Hologram.Test.Fixtures.Policy
  alias Hologram.Test.Fixtures.Role

  @index_key {Hologram.Policy.Edges, :index}

  describe "derive/1" do
    # A derived field has no column - the rows and attributes its definition reads are what a change
    # to it is a change to.
    test "derives the data a derived field in a condition reads through its definition" do
      assert derive([Module42]) == %{
               {Module42, :read} => [
                 {:attributes, [:note_id]},
                 {:relationship_attributes, [:note], Module41, [:public]}
               ],
               {Module42, :update} => [{:attributes, [:caption]}]
             }
    end

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

    test "derives the edges a path in a condition reads" do
      defmodule PathFixture1 do
        use Hologram.Entity

        relationship :b, Module3

        allow :read, when: b.c_id == nil
      end

      assert derive([PathFixture1]) == %{
               {PathFixture1, :read} => [
                 {:attributes, [:b_id]},
                 {:relationship_attributes, [:b], Module3, [:c_id]}
               ]
             }
    end

    # Each reference field the path is followed through is an edge of its own, so a related row
    # moving to another one re-evaluates what leans on it.
    test "derives the edges of a path through two relationships" do
      defmodule PathFixture2 do
        use Hologram.Entity

        relationship :d, Module3

        allow :read, when: d.b.a == true
      end

      assert derive([PathFixture2]) == %{
               {PathFixture2, :read} => [
                 {:attributes, [:d_id]},
                 {:relationship_attributes, [:d], Module3, [:b_id]},
                 {:relationship_attributes, [:d, :b], Module2, [:a]}
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

    # Every reference field a path is followed through is read, a condition's attribute where the
    # path ends, and a delegation's target edges are lifted under the whole path.
    test "derives the edges of a condition, a delegation and a grant reference through a path" do
      assert derive([Policy.Module12]) == %{
               {Policy.Module12, :archive} => [
                 {:attributes, [:link_id]},
                 {:relationship_attributes, [:link], Module17, [:priority]}
               ],
               {Policy.Module12, :delete} => [
                 {:attributes, [:level, :parent_id]},
                 {:relationship_attributes, [:parent], Policy.Module5, [:parent_id]},
                 {:relationship_attributes, [:parent, :parent], Policy.Module1, [:priority]}
               ],
               {Policy.Module12, :publish} => [
                 {:attributes, [:parent_id]},
                 {:relationship_attributes, [:parent], Policy.Module5, [:parent_id]},
                 {:relationship_attributes, [:parent, :parent], Policy.Module1, [:parent_id]},
                 {:relationship_attributes, [:parent, :parent, :parent], Policy.Module2,
                  [:public]}
               ],
               {Policy.Module12, :read} => [
                 {:attributes, [:parent_id]},
                 {:relationship_attributes, [:parent], Policy.Module5, [:parent_id]},
                 {:relationship_attributes, [:parent, :parent], Policy.Module1, [:public]}
               ],
               {Policy.Module12, :triage} => [
                 {:attributes, [:parent_id]},
                 {:relationship_attributes, [:parent], Policy.Module5, [:parent_id]},
                 {:relationship_attributes, [:parent, :parent], Policy.Module1, [:created_at]}
               ],
               {Policy.Module12, :update} => [
                 {:attributes, [:parent_id]},
                 {:relationship_attributes, [:parent], Policy.Module5, [:parent_id]},
                 {:relationship_grants, [:parent, :parent], Policy.Module1, [:viewer]}
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

  # The cache is one term for the whole node, so these leave it empty, for the next read to derive
  # the project's real index.
  describe "index/0" do
    setup do
      on_exit(&reset_caches/0)

      reset_caches()
    end

    test "derives the index of the project's compiled data model" do
      assert index() == derive(Reflection.list_entities())
    end

    test "answers from the cache" do
      :persistent_term.put(@index_key, :cached)

      assert index() == :cached
    end

    test "keeps the derived index for the calls after it" do
      assert :persistent_term.get(@index_key, nil) == nil

      derived = index()

      assert :persistent_term.get(@index_key, nil) == derived
    end
  end

  describe "reset_index_cache/0" do
    setup do
      on_exit(&reset_caches/0)

      reset_caches()
    end

    test "drops the cached index" do
      index()

      assert reset_index_cache() == :ok
      assert :persistent_term.get(@index_key, nil) == nil
    end
  end

  describe "universal_edges/0" do
    test "names the session-wide invalidation kinds" do
      assert universal_edges() == [:auth_change, :deploy]
    end
  end

  # The index is derived from the model cache, which an earlier test may have left holding
  # something other than the project's model.
  defp reset_caches do
    Model.reset_caches()
    reset_index_cache()
  end
end
