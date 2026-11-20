defmodule Hologram.Sync.SearchTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Search

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Oplog
  alias Hologram.Policy.Edges
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module30
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module12, as: PolicyModule12
  alias Hologram.Test.Fixtures.Policy.Module13, as: PolicyModule13
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyModule17
  alias Hologram.Test.Fixtures.Policy.Module18, as: PolicyModule18
  alias Hologram.Test.Fixtures.Policy.Module19, as: PolicyModule19
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module20, as: PolicyModule20
  alias Hologram.Test.Fixtures.Policy.Module21, as: PolicyModule21
  alias Hologram.Test.Fixtures.Policy.Module25, as: PolicyModule25
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5
  alias Hologram.Test.Fixtures.Role.Module1, as: RoleModule1
  alias Hologram.Test.Fixtures.Role.Module2, as: RoleModule2

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

  # Module17's archive rule reads none(label <- labels, label.name == "locked"): the labels' names,
  # and the pairs of its own to-many that put labels into the set. Asked as a read rule here.
  @labels_edges %{
    {PolicyModule17, :read} => [
      {:set_attributes, [:labels], PolicyModule19, [:name]},
      {:set_edges, [:labels], PolicyModule17, [:labels]}
    ]
  }

  # Module21's read rule reads any(task <- tasks, task.subject == "open"): the tasks' subjects, and
  # the pairs of Module20's to-many it is the inverse of.
  @tasks_edges %{
    {PolicyModule21, :read} => [
      {:set_attributes, [:tasks], PolicyModule20, [:subject]},
      {:set_edges, [:tasks], PolicyModule20, [:tags]}
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

  defp link!(source, relationship_name, target) do
    :ok =
      EntityOperations.add_relationship(
        source.__struct__,
        source.id,
        relationship_name,
        target.id
      )
  end

  defp pair_effect(op, source, relationship_name, target) do
    data = %{"relationship" => Atom.to_string(relationship_name), "target_id" => target.id}

    effect(op, source.__struct__, source.id, data)
  end

  # The effects the given writes record on the grant store, as the log reads them back.
  defp grant_effects(fun) do
    before = Oplog.read_type_after(RoleGrant, 0, 0, %{})

    fun.()

    RoleGrant
    |> Oplog.read_type_after(0, 0, %{})
    |> Enum.drop(length(before))
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

    # Module12's delete rule reads parent.parent.priority, which no read rule or verdict reads.
    test "follows no other operation's edges" do
      %{top: top} = seed_chain()

      edges = Edges.derive([PolicyModule1, PolicyModule5, PolicyModule12])
      effects = [effect(:patch_entity, PolicyModule1, top.id, %{"priority" => 3})]

      assert candidates(effects, edges) == %{rows: %{}, whole_types: %{}}
    end

    # Module17's archive rule reads none(label <- labels, label.name == "locked"), which no read
    # rule reads - a none the server answers browsers with its verdict, which reads the labels'
    # names and the pairs putting labels into the set.
    test "follows the verdicts' edges the policies derive" do
      project = create!(PolicyModule17)
      other_project = create!(PolicyModule17)
      label = create!(PolicyModule19)
      link!(project, :labels, label)

      edges = Edges.derive([PolicyModule17, PolicyModule18])
      renamed = [effect(:patch_entity, PolicyModule19, label.id, %{"name" => "locked"})]
      linked = [pair_effect(:add_relationship, other_project, :labels, label)]

      refute Enum.any?(edges[{PolicyModule17, :read}], &match?({_kind, [:labels | _], _, _}, &1))

      assert candidates(renamed, edges) == %{
               rows: %{PolicyModule17 => ids([project])},
               whole_types: %{}
             }

      assert candidates(linked, edges).rows == %{PolicyModule17 => ids([other_project])}
    end

    # A line named :verdicts is keyed by its name, as an operation is, and a browser answers it from
    # the rows it holds - so its edges are not the verdicts' and lead to no check.
    test "follows no edges of a line named :verdicts" do
      project = create!(PolicyModule17)
      label = create!(PolicyModule19)
      link!(project, :labels, label)

      derived = Edges.derive([PolicyModule17, PolicyModule18])
      verdict_edges = Map.fetch!(derived, {PolicyModule17, {:verdicts}})

      edges =
        derived
        |> Map.delete({PolicyModule17, {:verdicts}})
        |> Map.put({PolicyModule17, :verdicts}, verdict_edges)

      renamed = [effect(:patch_entity, PolicyModule19, label.id, %{"name" => "locked"})]

      assert candidates(renamed, edges) == %{rows: %{}, whole_types: %{}}
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

    test "lists the rows holding a row of a to-many set patched on a column the edge names" do
      label = create!(PolicyModule19)
      projects = [create!(PolicyModule17), create!(PolicyModule17)]
      other_project = create!(PolicyModule17)

      Enum.each(projects, &link!(&1, :labels, label))
      link!(other_project, :labels, create!(PolicyModule19))

      effects = [effect(:patch_entity, PolicyModule19, label.id, %{"name" => "locked"})]

      assert candidates(effects, @labels_edges).rows == %{PolicyModule17 => ids(projects)}
    end

    test "lists the source of a pair added to or removed from a to-many the edge names" do
      project = create!(PolicyModule17)
      other_project = create!(PolicyModule17)
      label = create!(PolicyModule19)

      effects = [
        pair_effect(:add_relationship, project, :labels, label),
        pair_effect(:del_relationship, other_project, :labels, label)
      ]

      assert candidates(effects, @labels_edges).rows == %{
               PolicyModule17 => ids([project, other_project])
             }
    end

    test "lists nothing for a pair of a to-many the edge doesn't name" do
      project = create!(PolicyModule17)
      label = create!(PolicyModule19)

      data = %{"relationship" => "watchers", "target_id" => label.id}
      effects = [effect(:add_relationship, PolicyModule17, project.id, data)]

      assert candidates(effects, @labels_edges) == %{rows: %{}, whole_types: %{}}
    end

    test "raises for a pair read without its data" do
      effects = [effect(:add_relationship, PolicyModule17, @unknown_id, nil)]

      assert_raise FunctionClauseError, fn -> candidates(effects, @labels_edges) end
    end

    test "lists the rows whose inverse of a to-many holds a row patched on a named column" do
      task = create!(PolicyModule20)
      tags = [create!(PolicyModule21), create!(PolicyModule21)]
      other_task = create!(PolicyModule20)

      Enum.each(tags, &link!(task, :tags, &1))
      link!(other_task, :tags, create!(PolicyModule21))

      effects = [effect(:patch_entity, PolicyModule20, task.id, %{"subject" => "open"})]

      assert candidates(effects, @tasks_edges).rows == %{PolicyModule21 => ids(tags)}
    end

    test "lists the target of a pair of the to-many an inverse reverses" do
      task = create!(PolicyModule20)
      tag = create!(PolicyModule21)

      effects = [pair_effect(:del_relationship, task, :tags, tag)]

      assert candidates(effects, @tasks_edges).rows == %{PolicyModule21 => ids([tag])}
    end

    # The log holds a target id as the write was given it, which need not be the form the rows'
    # ids take.
    test "lists the target of a pair in the form every listed id takes" do
      task = create!(PolicyModule20)
      tag = create!(PolicyModule21)

      data = %{"relationship" => "tags", "target_id" => String.replace(tag.id, "-", "")}
      effects = [effect(:del_relationship, PolicyModule20, task.id, data)]

      assert candidates(effects, @tasks_edges).rows == %{PolicyModule21 => ids([tag])}
    end

    # The delete takes the pairs with it, so only the effects it recorded name the tags.
    test "lists the rows whose inverse of a to-many held a deleted row" do
      task = create!(PolicyModule20)
      tags = [create!(PolicyModule21), create!(PolicyModule21)]

      Enum.each(tags, &link!(task, :tags, &1))

      DB.delete!(task)

      effects =
        PolicyModule20
        |> Oplog.read_type_after(0, 0, %{})
        |> Enum.filter(&(&1.op in [:del_relationship, :del_entity]))

      assert candidates(effects, @tasks_edges).rows == %{PolicyModule21 => ids(tags)}
    end

    test "lists the rows a to-many reached from the rows of a set leads back to" do
      project = create!(PolicyModule17)
      other_project = create!(PolicyModule17)
      task = create!(PolicyModule20, project_id: project.id)
      other_task = create!(PolicyModule20, project_id: other_project.id)
      tag = create!(PolicyModule21)

      link!(task, :tags, tag)
      link!(other_task, :tags, create!(PolicyModule21))

      edges = %{
        {PolicyModule17, :read} => [
          {:set_attributes, [:tasks, :tags], PolicyModule21, [:name]},
          {:set_edges, [:tasks, :tags], PolicyModule20, [:tags]}
        ]
      }

      assert candidates(
               [effect(:patch_entity, PolicyModule21, tag.id, %{"name" => "done"})],
               edges
             ).rows == %{PolicyModule17 => ids([project])}

      assert candidates([pair_effect(:add_relationship, task, :tags, tag)], edges).rows == %{
               PolicyModule17 => ids([project])
             }
    end

    test "lists the rows an inverse of a to-many reached through another link leads back to" do
      task = create!(PolicyModule20)
      sharing_task = create!(PolicyModule20)
      other_task = create!(PolicyModule20)
      tag = create!(PolicyModule21)

      link!(task, :tags, tag)
      link!(sharing_task, :tags, tag)
      link!(other_task, :tags, create!(PolicyModule21))

      edges = %{
        {PolicyModule20, :read} => [
          {:set_attributes, [:tags, :tasks], PolicyModule20, [:subject]},
          {:set_edges, [:tags, :tasks], PolicyModule20, [:tags]}
        ]
      }

      effects = [effect(:patch_entity, PolicyModule20, task.id, %{"subject" => "open"})]

      assert candidates(effects, edges).rows == %{PolicyModule20 => ids([task, sharing_task])}

      # The removed pair's target is the tag whose set lost the task, and the walk goes on from it
      # to the tasks still holding it - taking the pair's source instead would list nothing.
      :ok = EntityOperations.delete_relationship(PolicyModule20, task.id, :tags, tag.id)

      pair_effects = [pair_effect(:del_relationship, task, :tags, tag)]

      assert candidates(pair_effects, edges).rows == %{PolicyModule20 => ids([sharing_task])}
    end

    # The type's to-many and its inverse share one join table, so the chain's last link alone tells
    # which end of a pair holds the set.
    test "lists the rows of a self-referential to-many and its inverse from each end of a pair" do
      [a, b, c, d] = Enum.map(1..4, fn _index -> create!(Module30, body: "x") end)

      link!(c, :follows, a)
      link!(b, :follows, d)
      link!(a, :follows, b)

      follows_edges = %{{Module30, :read} => [{:set_edges, [:follows], Module30, [:follows]}]}
      followers_edges = %{{Module30, :read} => [{:set_edges, [:followers], Module30, [:follows]}]}

      two_hop_edges = %{
        {Module30, :read} => [{:set_edges, [:follows, :follows], Module30, [:follows]}]
      }

      two_hop_inverse_edges = %{
        {Module30, :read} => [{:set_edges, [:followers, :followers], Module30, [:follows]}]
      }

      pair_effects = [pair_effect(:add_relationship, a, :follows, b)]

      assert candidates(pair_effects, follows_edges).rows == %{Module30 => ids([a])}
      assert candidates(pair_effects, followers_edges).rows == %{Module30 => ids([b])}
      assert candidates(pair_effects, two_hop_edges).rows == %{Module30 => ids([c])}
      assert candidates(pair_effects, two_hop_inverse_edges).rows == %{Module30 => ids([d])}
    end

    test "follows the join table edges the policies derive" do
      task = create!(PolicyModule20)
      tag = create!(PolicyModule21)
      project = create!(PolicyModule17)
      shelved = create!(PolicyModule20, project_id: project.id)

      link!(task, :tags, tag)
      link!(shelved, :tags, tag)

      edges = Edges.derive([PolicyModule21])
      effects = [effect(:patch_entity, PolicyModule20, task.id, %{"subject" => "open"})]

      assert candidates(effects, edges) == %{
               rows: %{PolicyModule21 => ids([tag])},
               whole_types: %{}
             }

      pair_effects = [pair_effect(:add_relationship, task, :tags, tag)]

      assert candidates(pair_effects, edges).rows == %{PolicyModule21 => ids([tag])}

      # Module17's close rule reads any(tag <- tasks.tags, tag.name == "done"), asked as a read
      # rule.
      close_edges = %{
        {PolicyModule17, :read} => Edges.derive([PolicyModule17])[{PolicyModule17, :close}]
      }

      tag_effects = [effect(:patch_entity, PolicyModule21, tag.id, %{"name" => "done"})]

      assert candidates(tag_effects, close_edges).rows == %{PolicyModule17 => ids([project])}

      shelved_effects = [pair_effect(:add_relationship, shelved, :tags, tag)]

      assert candidates(shelved_effects, close_edges).rows == %{PolicyModule17 => ids([project])}
    end

    test "lists the row an own role is granted on" do
      user = create!(Module14, email: "a@b.c")
      resource = create!(PolicyModule1)
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:viewer]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :viewer, resource) end)

      assert candidates(effects, edges) == %{
               rows: %{PolicyModule1 => ids([resource])},
               whole_types: %{}
             }
    end

    test "names the holder of an own role granted on the whole type" do
      user = create!(Module14, email: "a@b.c")
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:viewer]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :viewer, PolicyModule1) end)

      assert candidates(effects, edges) == %{
               rows: %{},
               whole_types: %{PolicyModule1 => MapSet.new([user.id])}
             }
    end

    # A rule of an operation the server sends a verdict on can name the role, which moves the
    # verdicts of every row of the type its holder may read.
    test "names the holder of an own role granted on the whole type a verdict edge names" do
      user = create!(Module14, email: "a@b.c")
      edges = %{{PolicyModule1, {:verdicts}} => [{:own_grants, [:viewer]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :viewer, PolicyModule1) end)

      assert candidates(effects, edges) == %{
               rows: %{},
               whole_types: %{PolicyModule1 => MapSet.new([user.id])}
             }
    end

    test "lists nothing for a role the edge doesn't name" do
      user = create!(Module14, email: "a@b.c")
      resource = create!(PolicyModule1)
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:viewer]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :editor, resource) end)

      assert candidates(effects, edges) == %{rows: %{}, whole_types: %{}}
    end

    test "lists the same row for a revoke as for the grant" do
      user = create!(Module14, email: "a@b.c")
      resource = create!(PolicyModule1)
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:viewer]}]}

      Auth.grant_role(user, :viewer, resource)

      effects = grant_effects(fn -> Auth.revoke_role(user, :viewer, resource) end)

      assert [%{op: :del_entity}] = effects
      assert candidates(effects, edges).rows == %{PolicyModule1 => ids([resource])}
    end

    test "lists nothing for a role of the name the edge names held on another type" do
      user = create!(Module14, email: "a@b.c")
      group = create!(PolicyModule2)
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:member]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :member, group) end)

      assert candidates(effects, edges) == %{rows: %{}, whole_types: %{}}
    end

    test "passes over a grant effect of an op that changes no grant" do
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:viewer]}]}

      effects = [
        effect(:patch_entity, RoleGrant, @unknown_id, %{}),
        effect("merge_entity", RoleGrant, @unknown_id, %{})
      ]

      assert candidates(effects, edges) == %{rows: %{}, whole_types: %{}}
    end

    test "names the holder of another type's role granted on that whole type" do
      user = create!(Module14, email: "a@b.c")
      edges = %{{PolicyModule1, :read} => [{:type_grants, PolicyModule2, [:admin]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :admin, PolicyModule2) end)

      assert candidates(effects, edges) == %{
               rows: %{},
               whole_types: %{PolicyModule1 => MapSet.new([user.id])}
             }
    end

    test "lists nothing for another type's role granted on one of its rows" do
      user = create!(Module14, email: "a@b.c")
      group = create!(PolicyModule2)
      edges = %{{PolicyModule1, :read} => [{:type_grants, PolicyModule2, [:admin]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :admin, group) end)

      assert candidates(effects, edges) == %{rows: %{}, whole_types: %{}}
    end

    test "names the holder of a global role" do
      user = create!(Module14, email: "a@b.c")
      edges = %{{RoleGrant, :read} => [{:global_grants, [RoleModule1]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, RoleModule1) end)

      assert candidates(effects, edges) == %{
               rows: %{},
               whole_types: %{RoleGrant => MapSet.new([user.id])}
             }
    end

    # Role.Module2 extends Role.Module1, so the grant store's rule reading Module1 holders reads
    # Module2's too.
    test "names the holder of a global role extending one a rule reads" do
      user = create!(Module14, email: "a@b.c")
      edges = Edges.derive([RoleGrant])

      effects = grant_effects(fn -> Auth.grant_role(user, RoleModule2) end)

      assert candidates(effects, edges).whole_types == %{RoleGrant => MapSet.new([user.id])}
    end

    # A delegation to a grant carries the store's named edge without the chain to the grant.
    test "names the holder of a named role for a type other than the grant store" do
      user = create!(Module14, email: "a@b.c")
      group = create!(PolicyModule2)
      edges = %{{PolicyModule13, :read} => [{:named_grants, PolicyModule2, [:member]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :member, group) end)

      assert candidates(effects, edges) == %{
               rows: %{},
               whole_types: %{PolicyModule13 => MapSet.new([user.id])}
             }
    end

    test "lists the rows a chain leads back to from the row a related role is granted on" do
      user = create!(Module14, email: "a@b.c")
      group = create!(PolicyModule2)
      other_group = create!(PolicyModule2)

      children = [
        create!(PolicyModule13, parent_id: group.id),
        create!(PolicyModule13, parent_id: group.id)
      ]

      create!(PolicyModule13, parent_id: other_group.id)

      edges = %{
        {PolicyModule13, :read} => [{:relationship_grants, [:parent], PolicyModule2, [:member]}]
      }

      effects = grant_effects(fn -> Auth.grant_role(user, :member, group) end)

      assert candidates(effects, edges) == %{
               rows: %{PolicyModule13 => ids(children)},
               whole_types: %{}
             }
    end

    # Module5 delegates its read to its parent's, so Module1's own viewer role is held on Module5's
    # parent - and the delegated rule still matches it held on Module1's whole type.
    test "follows a role a delegation reads, on one row and on the whole type" do
      user = create!(Module14, email: "a@b.c")
      resource = create!(PolicyModule1)
      children = [create!(PolicyModule5, parent_id: resource.id)]
      other_resource = create!(PolicyModule1)
      create!(PolicyModule5, parent_id: other_resource.id)

      edges = Edges.derive([PolicyModule5])

      row_effects = grant_effects(fn -> Auth.grant_role(user, :viewer, resource) end)

      assert candidates(row_effects, edges) == %{
               rows: %{PolicyModule5 => ids(children)},
               whole_types: %{}
             }

      type_effects = grant_effects(fn -> Auth.grant_role(user, :viewer, PolicyModule1) end)

      assert candidates(type_effects, edges) == %{
               rows: %{},
               whole_types: %{PolicyModule5 => MapSet.new([user.id])}
             }
    end

    test "lists the grants naming the row a named role is granted on" do
      user = create!(Module14, email: "a@b.c")
      other_user = create!(Module14, email: "d@e.f")
      group = create!(PolicyModule2)
      other_group = create!(PolicyModule2)

      Auth.grant_role(other_user, :admin, group)
      Auth.grant_role(other_user, :member, other_group)

      edges = %{{RoleGrant, :read} => [{:named_grants, PolicyModule2, [:admin, :member]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :member, group) end)

      grant_ids =
        MapSet.new([
          RoleGrant.derive_id(other_user.id, PolicyModule2, group.id, :admin),
          RoleGrant.derive_id(user.id, PolicyModule2, group.id, :member)
        ])

      assert candidates(effects, edges) == %{rows: %{RoleGrant => grant_ids}, whole_types: %{}}
    end

    test "lists nothing for a named role granted on the whole type" do
      user = create!(Module14, email: "a@b.c")
      other_user = create!(Module14, email: "d@e.f")

      Auth.grant_role(other_user, :admin, create!(PolicyModule2))

      edges = %{{RoleGrant, :read} => [{:named_grants, PolicyModule2, [:admin, :member]}]}

      effects = grant_effects(fn -> Auth.grant_role(user, :member, PolicyModule2) end)

      assert candidates(effects, edges) == %{rows: %{}, whole_types: %{}}
    end

    test "raises for a grant read without its data" do
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:viewer]}]}
      effects = [effect(:put_entity, RoleGrant, @unknown_id, nil)]

      assert_raise FunctionClauseError, fn -> candidates(effects, edges) end
    end

    test "follows the grant edges the policies derive" do
      user = create!(Module14, email: "a@b.c")
      group = create!(PolicyModule2)
      child = create!(PolicyModule13, parent_id: group.id)

      edges = Edges.derive([PolicyModule1, PolicyModule2, PolicyModule13, RoleGrant])

      effects = grant_effects(fn -> Auth.grant_role(user, :member, group) end)
      [%{entity_id: grant_id}] = effects

      assert candidates(effects, edges) == %{
               rows: %{
                 PolicyModule13 => ids([child]),
                 PolicyModule2 => ids([group]),
                 RoleGrant => MapSet.new([grant_id])
               },
               whole_types: %{}
             }
    end
  end

  describe "join_table/3" do
    test "returns the join table of a to-many" do
      assert join_table(DB.mapping(), PolicyModule17, :labels) ==
               "test_fixtures_policy_module17_labels_$join"
    end

    test "raises for a relationship the mapping has no join table for" do
      assert_raise ArgumentError,
                   "no join table for Hologram.Test.Fixtures.Policy.Module17.nope in the mapping",
                   fn -> join_table(DB.mapping(), PolicyModule17, :nope) end
    end
  end
end
