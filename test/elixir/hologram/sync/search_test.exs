defmodule Hologram.Sync.SearchTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Search

  alias Hologram.DB
  alias Hologram.Policy.Edges
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module12, as: PolicyModule12
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
  end
end
