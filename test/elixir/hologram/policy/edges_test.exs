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

  @stale_model_msg "the code changed since the last compile that validated the data model - fix the compile error, if there is one, and save again"

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

  describe "derive/1 - quantifiers" do
    defmodule EdgeProject do
      use Hologram.Entity

      attribute :name, :string

      relationship :labels, [Hologram.Policy.EdgesTest.EdgeLabel]
      relationship :members, [Hologram.Policy.EdgesTest.EdgeMember], inverse: project

      allow :read, when: any(member <- members, member.seat == "full")
      allow :update, when: any(members)
      allow :delete, when: none(label <- labels, label.name == "x")
      allow :archive, when: any(labels)
    end

    defmodule EdgeMember do
      use Hologram.Entity

      attribute :first, :string
      attribute :last, :string
      attribute :seat, :string

      relationship :project, EdgeProject, optional: true
      relationship :user, Module14, optional: true

      derived :full, :string, fn first, last -> first <> last end

      allow :read
    end

    defmodule EdgeLabel do
      use Hologram.Entity

      attribute :name, :string

      relationship :projects, [EdgeProject], inverse: labels

      allow :read, when: any(project <- projects, project.name == "x")
    end

    defmodule EdgeTask do
      use Hologram.Entity

      relationship :project, EdgeProject, optional: true

      allow :read, when: any(member <- project.members, member.user_id == user_id())
      allow :update, when: any(member <- project.members, member.user.email == "a")

      allow :delete,
        when: any(label <- project.labels, any(project <- label.projects, project.name == "y"))
    end

    defmodule EdgeSeat do
      use Hologram.Entity

      attribute :seat, :string

      relationship :project, EdgeProject, optional: true

      allow :read, when: seat == "a" or any(member <- project.members, member.full == seat)

      allow :update,
        when: any(member <- project.members, any(label <- project.labels, label.name == "x"))
    end

    defmodule EdgeNote do
      use Hologram.Entity

      relationship :task, EdgeTask, optional: true

      allow :read, via: task
    end

    # A member joins or leaves the project's set by its reference field, which its edge names beside
    # what the condition reads.
    test "derives the edges of an inverse set of a to-one with a condition and without one" do
      edges = derive([EdgeProject])

      assert edges[{EdgeProject, :read}] == [
               {:set_attributes, [:members], EdgeMember, [:project_id, :seat]}
             ]

      assert edges[{EdgeProject, :update}] == [
               {:set_attributes, [:members], EdgeMember, [:project_id]}
             ]
    end

    test "derives the edges of a to-many set" do
      assert derive([EdgeProject])[{EdgeProject, :delete}] == [
               {:set_attributes, [:labels], EdgeLabel, [:name]},
               {:set_edges, [:labels], EdgeProject, [:labels]}
             ]
    end

    # The labels are never read, but a pair added to the project's to-many puts one into the set.
    test "derives the edges of a to-many set its condition reads nothing on" do
      assert derive([EdgeProject])[{EdgeProject, :archive}] == [
               {:set_edges, [:labels], EdgeProject, [:labels]}
             ]
    end

    test "derives the edges of an inverse set of a to-many" do
      assert derive([EdgeLabel])[{EdgeLabel, :read}] == [
               {:set_attributes, [:projects], EdgeProject, [:name]},
               {:set_edges, [:projects], EdgeProject, [:labels]}
             ]
    end

    test "derives the edges of a set reached through a relationship" do
      assert derive([EdgeTask])[{EdgeTask, :read}] == [
               {:attributes, [:project_id]},
               {:set_attributes, [:project, :members], EdgeMember, [:project_id, :user_id]}
             ]
    end

    test "derives the edges of a path followed from the rows of a set" do
      assert derive([EdgeTask])[{EdgeTask, :update}] == [
               {:attributes, [:project_id]},
               {:set_attributes, [:project, :members], EdgeMember, [:project_id, :user_id]},
               {:set_attributes, [:project, :members, :user], Module14, [:email]}
             ]
    end

    test "derives the edges of a quantifier nested in another's condition" do
      assert derive([EdgeTask])[{EdgeTask, :delete}] == [
               {:attributes, [:project_id]},
               {:set_attributes, [:project, :labels, :projects], EdgeProject, [:name]},
               {:set_edges, [:project, :labels], EdgeProject, [:labels]},
               {:set_edges, [:project, :labels, :projects], EdgeProject, [:labels]}
             ]
    end

    # The row's own seat is read inside the quantifier, beside the alternative reading it outside,
    # and the derived field reads its definition's attributes on the set's rows.
    test "derives the edges of a quantifier in an alternative reading the row it is about" do
      assert derive([EdgeSeat])[{EdgeSeat, :read}] == [
               {:attributes, [:project_id, :seat]},
               {:set_attributes, [:project, :members], EdgeMember, [:first, :last, :project_id]}
             ]
    end

    test "derives the edges of a set a nested quantifier reads on a row above" do
      assert derive([EdgeSeat])[{EdgeSeat, :update}] == [
               {:attributes, [:project_id]},
               {:set_attributes, [:project, :labels], EdgeLabel, [:name]},
               {:set_attributes, [:project, :members], EdgeMember, [:project_id]},
               {:set_edges, [:project, :labels], EdgeProject, [:labels]}
             ]
    end

    # The delete rule's none is answered from the server's verdict, sent with every project, so what
    # it reads is named apart from the operations - beside the operation's own edges.
    test "names what the deciding quantifiers read under :verdicts" do
      assert derive([EdgeProject])[{EdgeProject, :verdicts}] == [
               {:set_attributes, [:labels], EdgeLabel, [:name]},
               {:set_edges, [:labels], EdgeProject, [:labels]}
             ]
    end

    test "names no :verdicts edges for a type with no deciding quantifier" do
      refute [EdgeLabel]
             |> derive()
             |> Map.has_key?({EdgeLabel, :verdicts})
    end

    test "lifts a set's edges through a delegation" do
      assert derive([EdgeNote])[{EdgeNote, :read}] == [
               {:attributes, [:task_id]},
               {:relationship_attributes, [:task], EdgeTask, [:project_id]},
               {:set_attributes, [:task, :project, :members], EdgeMember, [:project_id, :user_id]}
             ]
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

    test "raises when the model is under a hold, even when cached" do
      on_exit(&Model.release/0)

      index()
      Model.hold()

      assert_error Hologram.StaleModelError, @stale_model_msg, fn -> index() end
    end

    # A dev VM whose compile refused a via cycle has the cycle's modules loaded and named by the
    # model cache. Deriving from them follows delegation forever, so the read is refused instead.
    # Run in a task, so that a derivation that does not end fails the test rather than hanging it.
    test "raises rather than derives when the model is under a hold" do
      defmodule InlineEdgesFixture1 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.EdgesTest.InlineEdgesFixture2, optional: true

        allow :read, via: peer
      end

      defmodule InlineEdgesFixture2 do
        use Hologram.Entity

        relationship :peer, Hologram.Policy.EdgesTest.InlineEdgesFixture1, optional: true

        allow :read, via: peer
      end

      on_exit(&Model.release/0)

      Model.put_facts([InlineEdgesFixture1, InlineEdgesFixture2], [], nil)
      Model.hold()

      task =
        Task.async(fn ->
          try do
            index()
          rescue
            error -> error
          end
        end)

      result = Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill)

      assert result == {:ok, %Hologram.StaleModelError{message: @stale_model_msg}}
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
