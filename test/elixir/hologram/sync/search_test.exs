defmodule Hologram.Sync.SearchTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Search

  alias Hologram.DB
  alias Hologram.DB.Oplog
  alias Hologram.Policy.Edges
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module12, as: PolicyModule12
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyModule17
  alias Hologram.Test.Fixtures.Policy.Module18, as: PolicyModule18
  alias Hologram.Test.Fixtures.Policy.Module20, as: PolicyModule20
  alias Hologram.Test.Fixtures.Policy.Module25, as: PolicyModule25
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5

  @unknown_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  # Module12's read rule reads parent.parent.public: the reference it is followed through on its
  # Module5, and the attribute on the Module1 there.
  @chain_edges %{
    {PolicyModule12, :read} => [
      {:attributes, [:parent_id]},
      {:relationship_attributes, [:parent], PolicyModule5, [:parent_id]},
      {:relationship_attributes, [:parent, :parent], PolicyModule1, [:public]}
    ]
  }

  # Module17's read rule reads any(member <- members, member.user_id == user_id()): the set of
  # Module18 rows whose project reference names it.
  @members_edges %{
    {PolicyModule17, :read} => [
      {:attributes, [:public]},
      {:set_attributes, [:members], PolicyModule18, [:project_id, :user_id]}
    ]
  }

  # An effect as the log reads it back: data and old references keyed by strings.
  defp effect(op, type, entity_id, data, old \\ nil) do
    %{data: data, entity_id: entity_id, old: old, op: op, type: type}
  end

  defp create!(entity_type, values \\ []) do
    values
    |> entity_type.new()
    |> DB.create!()
  end

  defp ids(rows) do
    rows
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  # Two Module1 rows, a Module5 under each, and Module12 rows under the Module5s - two under the
  # first, one under the second.
  defp seed_chain do
    top = create!(PolicyModule1)
    other_top = create!(PolicyModule1)

    middle = create!(PolicyModule5, parent_id: top.id)
    other_middle = create!(PolicyModule5, parent_id: other_top.id)

    bottoms = [
      create!(PolicyModule12, parent_id: middle.id),
      create!(PolicyModule12, parent_id: middle.id)
    ]

    other_bottom = create!(PolicyModule12, parent_id: other_middle.id)

    %{
      bottoms: bottoms,
      middle: middle,
      other_bottom: other_bottom,
      other_middle: other_middle,
      other_top: other_top,
      top: top
    }
  end

  describe "candidates/2" do
    test "lists the rows a chain of to-one references leads back to from a patched attribute" do
      %{bottoms: bottoms, top: top} = seed_chain()

      effects = [effect(:patch_entity, PolicyModule1, top.id, %{"public" => true})]

      assert candidates(effects, @chain_edges) == %{
               rows: %{PolicyModule12 => ids(bottoms)},
               whole_types: %{}
             }
    end

    test "lists nothing for a patch of a column the edges don't name" do
      %{top: top} = seed_chain()

      effects = [effect(:patch_entity, PolicyModule1, top.id, %{"priority" => 3})]

      assert candidates(effects, @chain_edges) == %{rows: %{}, whole_types: %{}}
    end

    test "lists the rows pointing at a row whose reference a chain is followed through moved" do
      %{bottoms: bottoms, middle: middle, other_top: other_top} = seed_chain()

      effects = [
        effect(:patch_entity, PolicyModule5, middle.id, %{"parent_id" => other_top.id})
      ]

      assert candidates(effects, @chain_edges) == %{
               rows: %{PolicyModule12 => ids(bottoms)},
               whole_types: %{}
             }
    end

    test "a put touches every name" do
      %{bottoms: bottoms, top: top} = seed_chain()

      effects = [effect(:put_entity, PolicyModule1, top.id, %{"priority" => 3})]

      assert candidates(effects, @chain_edges).rows == %{PolicyModule12 => ids(bottoms)}
    end

    test "a delete touches every name" do
      %{bottoms: bottoms, top: top} = seed_chain()

      effects = [effect(:del_entity, PolicyModule1, top.id, %{"priority" => 3})]

      assert candidates(effects, @chain_edges).rows == %{PolicyModule12 => ids(bottoms)}
    end

    test "unions the rows of effects reaching the same chain" do
      %{bottoms: bottoms, other_bottom: other_bottom, other_top: other_top, top: top} =
        seed_chain()

      effects = [
        effect(:patch_entity, PolicyModule1, top.id, %{"public" => true}),
        effect(:patch_entity, PolicyModule1, other_top.id, %{"public" => true})
      ]

      assert candidates(effects, @chain_edges).rows == %{
               PolicyModule12 => ids([other_bottom | bottoms])
             }
    end

    test "lists nothing for a row nothing points at" do
      seed_chain()

      effects = [effect(:patch_entity, PolicyModule1, @unknown_id, %{"public" => true})]

      assert candidates(effects, @chain_edges) == %{rows: %{}, whole_types: %{}}
    end

    test "passes over an effect of an entity type this node doesn't know" do
      effects = [effect(:patch_entity, "MyApp.Gone", @unknown_id, %{"public" => true})]

      assert candidates(effects, @chain_edges) == %{rows: %{}, whole_types: %{}}
    end

    test "passes over an effect of an op this node doesn't know" do
      %{top: top} = seed_chain()

      effects = [effect("merge_entity", PolicyModule1, top.id, %{"public" => true})]

      assert candidates(effects, @chain_edges) == %{rows: %{}, whole_types: %{}}
    end

    test "passes over an effect of an op this node knows as an atom for something else" do
      %{top: top} = seed_chain()

      effects = [effect(:merge, PolicyModule1, top.id, %{"public" => true})]

      assert candidates(effects, @chain_edges) == %{rows: %{}, whole_types: %{}}
    end

    test "raises for a put read without its data" do
      effects = [effect(:put_entity, PolicyModule1, @unknown_id, nil)]

      assert_raise FunctionClauseError, fn -> candidates(effects, @chain_edges) end
    end

    test "lists nothing for no effects" do
      assert candidates([], @chain_edges) == %{rows: %{}, whole_types: %{}}
    end

    test "lists nothing for an effect on a type no edge leads to" do
      %{bottoms: [bottom | _rest]} = seed_chain()

      effects = [effect(:patch_entity, PolicyModule12, bottom.id, %{"level" => 2})]

      assert candidates(effects, @chain_edges) == %{rows: %{}, whole_types: %{}}
    end

    test "lists nothing for an edge on the row's own attributes" do
      %{middle: middle, other_top: other_top} = seed_chain()

      edges = %{{PolicyModule5, :read} => [{:attributes, [:parent_id]}]}
      effects = [effect(:patch_entity, PolicyModule5, middle.id, %{"parent_id" => other_top.id})]

      assert candidates(effects, edges) == %{rows: %{}, whole_types: %{}}
    end

    test "follows the edges the policies derive" do
      %{bottoms: bottoms, middle: middle, top: top} = seed_chain()

      edges = Edges.derive([PolicyModule1, PolicyModule5, PolicyModule12])
      effects = [effect(:patch_entity, PolicyModule1, top.id, %{"public" => true})]

      assert candidates(effects, edges) == %{
               rows: %{PolicyModule12 => ids(bottoms), PolicyModule5 => ids([middle])},
               whole_types: %{}
             }
    end

    # Module12's delete rule reads parent.parent.priority, which no read rule reads.
    test "follows only the read rules' edges" do
      %{top: top} = seed_chain()

      edges = Edges.derive([PolicyModule1, PolicyModule5, PolicyModule12])
      effects = [effect(:patch_entity, PolicyModule1, top.id, %{"priority" => 3})]

      assert candidates(effects, edges) == %{rows: %{}, whole_types: %{}}
    end

    # The row is created outside the set, so only what the put recorded names the project.
    test "lists the row whose set a new row joins" do
      project = create!(PolicyModule17)
      member = create!(PolicyModule18)

      data = %{"project_id" => project.id, "seat" => nil, "user_id" => nil}
      effects = [effect(:put_entity, PolicyModule18, member.id, data)]

      assert candidates(effects, @members_edges).rows == %{PolicyModule17 => ids([project])}
    end

    test "lists the row whose set holds a row patched on a column the edge names" do
      project = create!(PolicyModule17)
      user = create!(Module14, email: "a@b.c")
      member = create!(PolicyModule18, project_id: project.id)

      effects = [effect(:patch_entity, PolicyModule18, member.id, %{"user_id" => user.id})]

      assert candidates(effects, @members_edges).rows == %{PolicyModule17 => ids([project])}
    end

    test "lists nothing for a row of a set patched on a column the edge doesn't name" do
      project = create!(PolicyModule17)
      member = create!(PolicyModule18, project_id: project.id)

      effects = [effect(:patch_entity, PolicyModule18, member.id, %{"seat" => "full"})]

      assert candidates(effects, @members_edges) == %{rows: %{}, whole_types: %{}}
    end

    test "lists the rows of both sets a moved row left and joined" do
      left = create!(PolicyModule17)
      joined = create!(PolicyModule17)
      member = create!(PolicyModule18, project_id: joined.id)

      effects = [
        effect(
          :patch_entity,
          PolicyModule18,
          member.id,
          %{"project_id" => joined.id},
          %{"project_id" => left.id}
        )
      ]

      assert candidates(effects, @members_edges).rows == %{
               PolicyModule17 => ids([left, joined])
             }
    end

    test "lists the row whose set a row left by unsetting its reference" do
      left = create!(PolicyModule17)
      member = create!(PolicyModule18)

      effects = [
        effect(:patch_entity, PolicyModule18, member.id, %{"project_id" => nil}, %{
          "project_id" => left.id
        })
      ]

      assert candidates(effects, @members_edges).rows == %{PolicyModule17 => ids([left])}
    end

    test "lists the row whose set a deleted row was in, from what the delete recorded" do
      project = create!(PolicyModule17)
      member = create!(PolicyModule18, project_id: project.id)

      DB.delete!(member)

      data = %{"project_id" => project.id, "seat" => nil, "user_id" => nil}
      effects = [effect(:del_entity, PolicyModule18, member.id, data)]

      assert candidates(effects, @members_edges).rows == %{PolicyModule17 => ids([project])}
    end

    # The effect names another row than the table does, so only reading the table lists the row the
    # profile now names.
    test "lists the row a single inverse of a to-one reads" do
      earlier = create!(PolicyModule17)
      project = create!(PolicyModule17)
      profile = create!(PolicyModule25, project_id: project.id)

      edges = %{
        {PolicyModule17, :read} => [{:set_attributes, [:profile], PolicyModule25, [:project_id]}]
      }

      effects = [
        effect(:patch_entity, PolicyModule25, profile.id, %{"project_id" => earlier.id}, %{
          "project_id" => nil
        })
      ]

      assert candidates(effects, edges).rows == %{PolicyModule17 => ids([earlier, project])}
    end

    test "lists the rows a path leads back to from the rows of a set" do
      left = create!(PolicyModule17)
      joined = create!(PolicyModule17)
      other = create!(PolicyModule17)
      member = create!(PolicyModule18, project_id: joined.id)

      tasks = [
        create!(PolicyModule20, project_id: left.id),
        create!(PolicyModule20, project_id: joined.id)
      ]

      create!(PolicyModule20, project_id: other.id)

      edges = %{
        {PolicyModule20, :read} => [
          {:attributes, [:project_id]},
          {:set_attributes, [:project, :members], PolicyModule18, [:project_id, :user_id]}
        ]
      }

      effects = [
        effect(
          :patch_entity,
          PolicyModule18,
          member.id,
          %{"project_id" => joined.id},
          %{"project_id" => left.id}
        )
      ]

      assert candidates(effects, edges).rows == %{PolicyModule20 => ids(tasks)}
    end

    test "lists the rows a to-one followed from the rows of a set leads back to" do
      user = create!(Module14, email: "a@b.c")
      other_user = create!(Module14, email: "d@e.f")
      projects = [create!(PolicyModule17), create!(PolicyModule17)]
      other_project = create!(PolicyModule17)

      Enum.each(projects, &create!(PolicyModule18, project_id: &1.id, user_id: user.id))
      create!(PolicyModule18, project_id: other_project.id, user_id: other_user.id)

      edges = %{
        {PolicyModule17, :read} => [{:set_attributes, [:members, :user], Module14, [:email]}]
      }

      effects = [effect(:patch_entity, Module14, user.id, %{"email" => "g@h.i"})]

      assert candidates(effects, edges).rows == %{PolicyModule17 => ids(projects)}
    end

    test "follows the effects the log recorded for a move and a delete" do
      left = create!(PolicyModule17)
      joined = create!(PolicyModule17)
      held = create!(PolicyModule17)
      moved = create!(PolicyModule18, project_id: left.id)
      deleted = create!(PolicyModule18, project_id: held.id)

      DB.update!(PolicyModule18, moved.id, project_id: joined.id)
      DB.delete!(deleted)

      effects =
        PolicyModule18
        |> Oplog.read_type_after(0, 0, %{})
        |> Enum.filter(&(&1.op in [:patch_entity, :del_entity]))

      assert candidates(effects, @members_edges).rows == %{
               PolicyModule17 => ids([left, joined, held])
             }
    end

    test "follows the set edges the policies derive" do
      left = create!(PolicyModule17)
      joined = create!(PolicyModule17)
      member = create!(PolicyModule18, project_id: joined.id)

      edges = Edges.derive([PolicyModule17, PolicyModule18])

      effects = [
        effect(
          :patch_entity,
          PolicyModule18,
          member.id,
          %{"project_id" => joined.id},
          %{"project_id" => left.id}
        )
      ]

      assert candidates(effects, edges) == %{
               rows: %{PolicyModule17 => ids([left, joined])},
               whole_types: %{}
             }
    end
  end
end
