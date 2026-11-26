defmodule Hologram.Sync.PotTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Pot

  alias Hologram.Entity.NotIncluded
  alias Hologram.Sync.Held
  alias Hologram.Sync.PackedIds
  alias Hologram.Sync.Pot
  alias Hologram.Test.Fixtures.Entity.Module30
  alias Hologram.Test.Fixtures.Policy.Module17, as: Project
  alias Hologram.Test.Fixtures.Policy.Module19, as: Label
  alias Hologram.Test.Fixtures.Policy.Module20, as: Task
  alias Hologram.Test.Fixtures.Policy.Module21, as: Tag

  # A project's labels are a to-many with no inverse. A task's tags are a to-many whose inverse,
  # tasks, the tag files. A Module30 follows other Module30 rows, and is followed back.
  @synced [Label, Module30, Project, Tag, Task]

  @labels {Project, :labels, Label}
  @tags {Task, :tags, Tag}
  @follows {Module30, :follows, Module30}

  @id_1 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e01"
  @id_2 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e02"
  @id_3 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e03"
  @id_4 "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e04"

  defp edge(op, type, entity_id, relationship, target_id) do
    %{
      entity_id: entity_id,
      op: op,
      relationship: relationship,
      target_id: target_id,
      type: type
    }
  end

  # Rows the client's own batches created, per entity type, packed as a part names them.
  defp created(ids_by_type) do
    Map.new(ids_by_type, fn {entity_type, ids} -> {entity_type, PackedIds.pack(ids)} end)
  end

  defp held(ids_by_type) do
    Enum.reduce(ids_by_type, Held.new(), fn {entity_type, ids}, held ->
      Held.add(held, entity_type, ids)
    end)
  end

  # What the session knows of a client holding the given ids.
  defp pot(ids_by_type) do
    ids_by_type
    |> held()
    |> Pot.from_held()
  end

  # A part as `Hologram.Sync.Live.parts/7` builds it: checked ids, readable rows, the batch's
  # pairs and its pair effects given as plain values, and packed here.
  defp part(opts) do
    readable =
      opts
      |> Keyword.get(:readable, [])
      |> Enum.group_by(& &1.__struct__)
      |> Map.new(fn {entity_type, rows} -> {entity_type, Map.new(rows, &{&1.id, &1})} end)

    readable_ids =
      Map.new(readable, fn {entity_type, rows} -> {entity_type, Map.keys(rows)} end)

    checked =
      readable_ids
      |> Map.merge(Keyword.get(opts, :unreadable, %{}), fn _type, ids, more -> ids ++ more end)
      |> Map.new(fn {entity_type, ids} -> {entity_type, PackedIds.pack(ids)} end)

    moved =
      opts
      |> Keyword.get(:moved, %{})
      |> Map.new(fn {entity_type, ids} -> {entity_type, PackedIds.pack(ids)} end)

    %{
      checked: checked,
      moved: moved,
      pair_effects: pack_pairs(Keyword.get(opts, :pair_effects, %{})),
      pairs: pack_pairs(Keyword.get(opts, :pairs, %{})),
      readable: readable,
      synced_types: Keyword.get(opts, :synced_types, @synced),
      verdicts: Keyword.get(opts, :verdicts, %{}),
      written: Keyword.get(opts, :written, %{})
    }
  end

  defp pack_pairs(pairs_by_key) do
    Map.new(pairs_by_key, fn {key, pairs} -> {key, PackedIds.pack_pairs(pairs)} end)
  end

  describe "decide/2" do
    test "hands over a row the user may read that the client doesn't hold, and holds it" do
      project = %Project{id: @id_1, name: "new", public: true}

      {news, told} = decide(Pot.new(), part(readable: [project]))

      assert [%Project{id: @id_1, name: "new"}] = news.appeared
      assert news.patched == []
      assert news.unsynced == []
      assert Held.member?(told.held, Project, @id_1)
    end

    test "patches a held row with the attributes the batch wrote" do
      project = %Project{id: @id_1, name: "renamed", public: true}
      part = part(readable: [project], written: %{@id_1 => MapSet.new(["name"])})

      {news, told} = decide(pot(%{Project => [@id_1]}), part)

      assert news.appeared == []
      assert news.patched == [{project, %{name: "renamed"}}]
      assert Held.ids(told.held, Project) == [@id_1]
    end

    test "passes over an attribute the row doesn't have" do
      project = %Project{id: @id_1, name: "renamed", public: true}
      part = part(readable: [project], written: %{@id_1 => MapSet.new(["colour"])})

      {news, _held} = decide(pot(%{Project => [@id_1]}), part)

      assert news.patched == []
    end

    test "tells nothing of a held row the batch didn't write" do
      project = %Project{id: @id_1, public: true}

      {news, told} = decide(pot(%{Project => [@id_1]}), part(readable: [project]))

      assert news == %{appeared: [], edges: [], hidden: [], patched: [], unsynced: []}
      assert Held.ids(told.held, Project) == [@id_1]
    end

    test "drops a held row the user may no longer read, and no longer holds it" do
      part = part(unreadable: %{Project => [@id_1]})

      {news, told} = decide(pot(%{Project => [@id_1, @id_2]}), part)

      assert news.unsynced == [{@id_1, Project}]
      assert Held.ids(told.held, Project) == [@id_2]
    end

    test "tells nothing of a row it doesn't hold that the user may not read" do
      part = part(unreadable: %{Project => [@id_1]})

      {news, told} = decide(Pot.new(), part)

      assert news == %{appeared: [], edges: [], hidden: [], patched: [], unsynced: []}
      assert told == Pot.new()
    end

    test "hands a row over with its sets, holding only the rows the client holds once told" do
      project = %Project{id: @id_1, public: true}
      appearing_label = %Label{id: @id_4}

      part =
        part(
          readable: [project, appearing_label],
          pairs: %{@labels => [{@id_1, @id_2}, {@id_1, @id_3}, {@id_1, @id_4}]}
        )

      {news, _held} = decide(pot(%{Label => [@id_2]}), part)

      handed_project = Enum.find(news.appeared, &(&1.id == @id_1))

      assert Enum.map(handed_project.labels, & &1.id) == [@id_2, @id_4]
    end

    test "hands a row over with its inverse sets" do
      tag = %Tag{id: @id_3}
      part = part(readable: [tag], pairs: %{@tags => [{@id_1, @id_3}, {@id_2, @id_3}]})

      {news, _held} = decide(pot(%{Task => [@id_1]}), part)

      assert [%Tag{tasks: [%Task{id: @id_1}]}] = news.appeared
    end

    test "hands a row over with no set of a type sync doesn't send" do
      project = %Project{id: @id_1, public: true}

      part =
        part(readable: [project], pairs: %{@labels => [{@id_1, @id_2}]}, synced_types: [Project])

      {news, _held} = decide(pot(%{Label => [@id_2]}), part)

      assert [%Project{labels: %NotIncluded{}}] = news.appeared
    end

    test "tells a pair the batch added when the client holds both ends" do
      part =
        part(
          readable: [%Project{id: @id_1, public: true}],
          pair_effects: %{@labels => [{@id_1, @id_2}]},
          pairs: %{@labels => [{@id_1, @id_2}]}
        )

      {news, _held} = decide(pot(%{Label => [@id_2], Project => [@id_1]}), part)

      assert news.edges == [edge(:add_relationship, Project, @id_1, "labels", @id_2)]
    end

    test "doesn't tell an added pair naming a row the client doesn't hold" do
      part =
        part(
          readable: [%Project{id: @id_1, public: true}],
          pair_effects: %{@labels => [{@id_1, @id_2}]},
          pairs: %{@labels => [{@id_1, @id_2}]}
        )

      {news, _held} = decide(pot(%{Project => [@id_1]}), part)

      assert news.edges == []
    end

    test "tells a pair the batch removed when the client holds the other end" do
      part =
        part(
          readable: [%Project{id: @id_1, public: true}],
          pair_effects: %{@labels => [{@id_1, @id_2}]}
        )

      {news, _held} = decide(pot(%{Label => [@id_2], Project => [@id_1]}), part)

      assert news.edges == [edge(:del_relationship, Project, @id_1, "labels", @id_2)]
    end

    test "tells a pair removed with a row the client drops in the same batch" do
      part =
        part(
          readable: [%Project{id: @id_1, public: true}],
          unreadable: %{Label => [@id_2]},
          pair_effects: %{@labels => [{@id_1, @id_2}]}
        )

      {news, _held} = decide(pot(%{Label => [@id_2], Project => [@id_1]}), part)

      assert news.edges == [edge(:del_relationship, Project, @id_1, "labels", @id_2)]
      assert news.unsynced == [{@id_2, Label}]
    end

    test "never names a row the client never held in a removed pair" do
      part =
        part(
          readable: [%Project{id: @id_1, public: true}],
          pair_effects: %{@labels => [{@id_1, @id_2}]}
        )

      {news, _held} = decide(pot(%{Project => [@id_1]}), part)

      assert news.edges == []
    end

    test "tells a pair under its target too, when the target files an inverse of it" do
      part =
        part(
          readable: [%Task{id: @id_1}, %Tag{id: @id_2}],
          pair_effects: %{@tags => [{@id_1, @id_2}]},
          pairs: %{@tags => [{@id_1, @id_2}]}
        )

      {news, _held} = decide(pot(%{Tag => [@id_2], Task => [@id_1]}), part)

      assert news.edges == [
               edge(:add_relationship, Task, @id_1, "tags", @id_2),
               edge(:add_relationship, Tag, @id_2, "tasks", @id_1)
             ]
    end

    test "tells no pair under a row it hands over whole, whose sets say it" do
      part =
        part(
          readable: [%Project{id: @id_1, public: true}],
          pair_effects: %{@labels => [{@id_1, @id_2}]},
          pairs: %{@labels => [{@id_1, @id_2}]}
        )

      {news, _held} = decide(pot(%{Label => [@id_2]}), part)

      assert news.edges == []
      assert [%Project{labels: [%Label{id: @id_2}]}] = news.appeared
    end

    test "files a row it hands over under the held rows whose sets hold it" do
      part =
        part(
          readable: [%Label{id: @id_2}, %Task{id: @id_3}],
          pairs: %{@labels => [{@id_1, @id_2}, {@id_4, @id_2}], @tags => [{@id_3, @id_4}]}
        )

      {news, _held} = decide(pot(%{Project => [@id_1], Tag => [@id_4]}), part)

      assert news.edges == [
               edge(:add_relationship, Project, @id_1, "labels", @id_2),
               edge(:add_relationship, Tag, @id_4, "tasks", @id_3)
             ]
    end

    test "takes a row it drops out of the held rows whose sets hold it" do
      part =
        part(
          unreadable: %{Label => [@id_2], Task => [@id_3]},
          pairs: %{@labels => [{@id_1, @id_2}], @tags => [{@id_3, @id_4}]}
        )

      held = held(%{Label => [@id_2], Project => [@id_1], Tag => [@id_4], Task => [@id_3]})

      {news, _held} = decide(Pot.from_held(held), part)

      assert news.edges == [
               edge(:del_relationship, Project, @id_1, "labels", @id_2),
               edge(:del_relationship, Tag, @id_4, "tasks", @id_3)
             ]
    end

    test "files a row of a to-many onto its own type under the held rows at either end" do
      part =
        part(
          readable: [%Module30{id: @id_1, body: "new"}],
          pairs: %{@follows => [{@id_1, @id_2}, {@id_2, @id_1}]}
        )

      {news, _held} = decide(pot(%{Module30 => [@id_2]}), part)

      assert news.edges == [
               edge(:add_relationship, Module30, @id_2, "followers", @id_1),
               edge(:add_relationship, Module30, @id_2, "follows", @id_1)
             ]

      assert [%Module30{followers: [%Module30{id: @id_2}], follows: [%Module30{id: @id_2}]}] =
               news.appeared
    end

    test "tells a removed pair naming a row the client was told to drop earlier" do
      dropping = part(readable: [%Task{id: @id_1}], unreadable: %{Tag => [@id_2]})

      {_news, told} = decide(pot(%{Tag => [@id_2], Task => [@id_1]}), dropping)

      removing =
        part(readable: [%Task{id: @id_1}], pair_effects: %{@tags => [{@id_1, @id_2}]})

      {news, _told} = decide(told, removing)

      assert news.edges == [edge(:del_relationship, Task, @id_1, "tags", @id_2)]
    end

    test "tells a removed pair naming a dropped row handed over again in the same batch" do
      dropping = part(readable: [%Task{id: @id_1}], unreadable: %{Tag => [@id_2]})

      {_news, told} = decide(pot(%{Tag => [@id_2], Task => [@id_1]}), dropping)

      handing_over_and_removing =
        part(
          readable: [%Task{id: @id_1}, %Tag{id: @id_2}],
          pair_effects: %{@tags => [{@id_1, @id_2}]}
        )

      {news, after_batch} = decide(told, handing_over_and_removing)

      assert news.edges == [edge(:del_relationship, Task, @id_1, "tags", @id_2)]
      assert after_batch.dropped == Held.new()
    end

    test "tells a removed pair under a held target when its dropped source is all of its type" do
      dropping = part(readable: [%Tag{id: @id_2}], unreadable: %{Task => [@id_1]})

      {_news, told} = decide(pot(%{Tag => [@id_2], Task => [@id_1]}), dropping)

      removing = part(readable: [%Tag{id: @id_2}], pair_effects: %{@tags => [{@id_1, @id_2}]})

      {news, _told} = decide(told, removing)

      assert news.edges == [edge(:del_relationship, Tag, @id_2, "tasks", @id_1)]
    end

    test "files a row handed over and a row dropped of one type under the held row naming both" do
      part =
        part(
          readable: [%Task{id: @id_1}, %Tag{id: @id_3}],
          unreadable: %{Tag => [@id_4]},
          pairs: %{@tags => [{@id_1, @id_3}, {@id_1, @id_4}]}
        )

      {news, _told} = decide(pot(%{Tag => [@id_4], Task => [@id_1]}), part)

      assert news.edges == [
               edge(:add_relationship, Task, @id_1, "tags", @id_3),
               edge(:del_relationship, Task, @id_1, "tags", @id_4)
             ]

      assert [%Tag{id: @id_3, tasks: [%Task{id: @id_1}]}] = news.appeared
    end

    test "forgets a dropped row once it is handed over again" do
      dropping = part(unreadable: %{Tag => [@id_2]})
      handing_over = part(readable: [%Tag{id: @id_2}])

      {_news, dropped} = decide(pot(%{Tag => [@id_2]}), dropping)
      {_news, handed_over} = decide(dropped, handing_over)

      assert Held.ids(dropped.dropped, Tag) == [@id_2]
      assert handed_over.dropped == Held.new()
      assert Held.ids(handed_over.held, Tag) == [@id_2]
    end

    test "tells a removed pair under the target that files an inverse of it" do
      part =
        part(
          readable: [%Task{id: @id_1}, %Tag{id: @id_2}],
          pair_effects: %{@tags => [{@id_1, @id_2}]}
        )

      {news, _told} = decide(pot(%{Tag => [@id_2], Task => [@id_1]}), part)

      assert news.edges == [
               edge(:del_relationship, Task, @id_1, "tags", @id_2),
               edge(:del_relationship, Tag, @id_2, "tasks", @id_1)
             ]
    end

    test "tells nothing of a pair effect under a row the client doesn't hold" do
      part =
        part(
          readable: [%Task{id: @id_1}],
          unreadable: %{Tag => [@id_2]},
          pair_effects: %{@tags => [{@id_1, @id_2}]},
          pairs: %{@tags => [{@id_1, @id_2}]}
        )

      {news, _told} = decide(pot(%{Task => [@id_1]}), part)

      assert news.edges == []
    end

    test "takes a pair still there out of the held end's set when its other end is dropped" do
      part =
        part(
          readable: [%Project{id: @id_1, public: true}],
          unreadable: %{Label => [@id_2]},
          pair_effects: %{@labels => [{@id_1, @id_2}]},
          pairs: %{@labels => [{@id_1, @id_2}]}
        )

      {news, _told} = decide(pot(%{Label => [@id_2], Project => [@id_1]}), part)

      assert news.edges == [edge(:del_relationship, Project, @id_1, "labels", @id_2)]
    end

    test "tells a fact the batch names twice once" do
      part =
        part(
          readable: [%Task{id: @id_1}],
          pair_effects: %{@tags => [{@id_1, @id_2}]},
          pairs: %{@tags => [{@id_1, @id_2}]}
        )

      {news, _told} = decide(pot(%{Tag => [@id_2]}), part)

      assert news.edges == [edge(:add_relationship, Tag, @id_2, "tasks", @id_1)]
    end

    test "hands a row paired with itself over with itself in its sets, and tells no pair" do
      part =
        part(
          readable: [%Module30{id: @id_1, body: "self"}],
          pairs: %{@follows => [{@id_1, @id_1}]}
        )

      {news, _told} = decide(Pot.new(), part)

      assert news.edges == []

      assert [%Module30{followers: [%Module30{id: @id_1}], follows: [%Module30{id: @id_1}]}] =
               news.appeared
    end

    test "changes nothing, and hands over and drops nothing again, when the same trusted part is decided twice" do
      part =
        part(
          readable: [%Project{id: @id_1, name: "renamed", public: true}, %Label{id: @id_3}],
          unreadable: %{Label => [@id_2]},
          written: %{@id_1 => MapSet.new(["name"])},
          pairs: %{@labels => [{@id_1, @id_3}]}
        )

      {first_news, first} = decide(pot(%{Label => [@id_2], Project => [@id_1]}), part)
      {second_news, second} = decide(first, part)

      assert second == first
      assert second_news.patched == first_news.patched
      assert second_news.appeared == []
      assert second_news.unsynced == []
    end
  end

  describe "decide/3" do
    test "hands every row the user may read over whole when held isn't trusted, filed under held rows" do
      project = %Project{id: @id_1, name: "renamed", public: true}

      part =
        part(
          readable: [project, %Label{id: @id_2}],
          written: %{@id_1 => MapSet.new(["name"])},
          pairs: %{@labels => [{@id_1, @id_2}]}
        )

      {news, told} =
        decide(pot(%{Label => [@id_2], Project => [@id_1]}), part, trust_held?: false)

      # Rows go out in id order within each type, the types in no order.
      appeared_ids =
        news.appeared
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert appeared_ids == [@id_1, @id_2]
      assert news.patched == []
      assert news.edges == []
      assert %Project{labels: [%Label{id: @id_2}]} = Enum.find(news.appeared, &(&1.id == @id_1))
      assert Held.ids(told.held, Project) == [@id_1]
    end

    test "files a row handed over whole when held isn't trusted under the held rows naming it" do
      part = part(readable: [%Label{id: @id_2}], pairs: %{@labels => [{@id_1, @id_2}]})

      {news, _told} =
        decide(pot(%{Label => [@id_2], Project => [@id_1]}), part, trust_held?: false)

      assert news.edges == [edge(:add_relationship, Project, @id_1, "labels", @id_2)]
    end

    test "still drops a held row the user may no longer read when held isn't trusted" do
      part = part(unreadable: %{Project => [@id_1]})

      {news, _told} = decide(pot(%{Project => [@id_1]}), part, trust_held?: false)

      assert news.unsynced == [{@id_1, Project}]
    end

    test "tells by hash the moved rows the user may not read that the client isn't taken to hold" do
      part =
        part(
          moved: %{Project => [@id_3, @id_1, @id_2]},
          readable: [%Project{id: @id_2, public: true}],
          unreadable: %{Project => [@id_1, @id_3]}
        )

      {news, told} = decide(pot(%{Project => [@id_3]}), part, hidden_salt: "q3Vx")

      assert news.hidden == [{Project, "q3Vx", [@id_1]}]
      assert news.unsynced == [{@id_3, Project}]
      assert Held.ids(told.dropped, Project) == [@id_3]
    end

    test "tells nothing by hash of a row the batch checked but didn't move" do
      part = part(unreadable: %{Project => [@id_1]})

      {news, _told} = decide(Pot.new(), part, hidden_salt: "q3Vx")

      assert news.hidden == []
    end

    test "tells nothing by hash without a salt" do
      part = part(moved: %{Project => [@id_1]}, unreadable: %{Project => [@id_1]})

      {news, _told} = decide(Pot.new(), part)

      assert news.hidden == []
    end
  end

  describe "decide/3 - rows the client's own batches created" do
    test "drops a created row the user may not read, among the dropped" do
      part = part(unreadable: %{Project => [@id_1]})

      {news, told} = decide(Pot.new(), part, created: created(%{Project => [@id_1]}))

      assert news.unsynced == [{@id_1, Project}]
      assert Held.ids(told.held, Project) == []
      assert Held.ids(told.dropped, Project) == [@id_1]
    end

    test "hands a created row the user may read over whole, and holds it" do
      project = %Project{id: @id_1, name: "new", public: true}

      {news, told} =
        decide(Pot.new(), part(readable: [project]), created: created(%{Project => [@id_1]}))

      assert [%Project{id: @id_1}] = news.appeared
      assert news.unsynced == []
      assert Held.ids(told.held, Project) == [@id_1]
    end

    test "drops a created row once when it is held" do
      part = part(unreadable: %{Project => [@id_1]})

      {news, _told} =
        decide(pot(%{Project => [@id_1]}), part, created: created(%{Project => [@id_1]}))

      assert news.unsynced == [{@id_1, Project}]
    end

    test "tells nothing of a created row it holds that the user may read and the batch didn't write" do
      project = %Project{id: @id_1, public: true}

      {news, _told} =
        decide(pot(%{Project => [@id_1]}), part(readable: [project]),
          created: created(%{Project => [@id_1]})
        )

      assert news == %{appeared: [], edges: [], hidden: [], patched: [], unsynced: []}
    end

    # A catch-up's chunk has the rows an earlier chunk settled taken out of what it checked.
    test "drops a created row the part doesn't check" do
      {news, _told} = decide(Pot.new(), part([]), created: created(%{Project => [@id_1]}))

      assert news.unsynced == [{@id_1, Project}]
    end

    test "drops created rows in id order beside the held rows of the type it drops" do
      part = part(unreadable: %{Project => [@id_1, @id_3]})

      {news, _told} =
        decide(pot(%{Project => [@id_3]}), part, created: created(%{Project => [@id_1]}))

      assert news.unsynced == [{@id_1, Project}, {@id_3, Project}]
    end

    test "takes a dropped created row out of the held rows whose sets hold it" do
      part = part(unreadable: %{Label => [@id_2]}, pairs: %{@labels => [{@id_1, @id_2}]})

      {news, _told} =
        decide(pot(%{Project => [@id_1]}), part, created: created(%{Label => [@id_2]}))

      assert news.edges == [edge(:del_relationship, Project, @id_1, "labels", @id_2)]
    end

    test "drops a created row by id alone when given a salt" do
      part = part(moved: %{Project => [@id_1, @id_2]}, unreadable: %{Project => [@id_1, @id_2]})

      {news, _told} =
        decide(Pot.new(), part, created: created(%{Project => [@id_1]}), hidden_salt: "q3Vx")

      assert news.hidden == [{Project, "q3Vx", [@id_2]}]
      assert news.unsynced == [{@id_1, Project}]
    end
  end

  describe "drop/3 and hand_over/3" do
    test "move rows between held and dropped" do
      dropped = drop(pot(%{Project => [@id_1, @id_2]}), Project, [@id_1, @id_3])

      assert Held.ids(dropped.held, Project) == [@id_2]
      assert Held.ids(dropped.dropped, Project) == [@id_1, @id_3]

      handed_over = hand_over(dropped, Project, [@id_3])

      assert Held.ids(handed_over.held, Project) == [@id_2, @id_3]
      assert Held.ids(handed_over.dropped, Project) == [@id_1]
    end
  end

  describe "reread/4" do
    test "hands over the rows read that the client doesn't hold, and drops the held ones left out" do
      rows = [%Project{id: @id_1, public: true}, %Project{id: @id_2, public: true}]

      {news, told} =
        reread(pot(%{Project => [@id_2, @id_3]}), Project, rows, fn _ids -> %{} end)

      assert Enum.map(news.appeared, & &1.id) == [@id_1]
      assert news.unsynced == [{@id_3, Project}]
      assert news.patched == []
      assert Held.ids(told.held, Project) == [@id_1, @id_2]
      assert Held.ids(told.dropped, Project) == [@id_3]
    end

    test "reads the pairs of the rows it hands over and drops, and tells them under held rows" do
      rows = [%Label{id: @id_2}]
      test_pid = self()

      read_pairs = fn ids_by_type ->
        send(test_pid, {:read_pairs, ids_by_type})

        %{@labels => PackedIds.pack_pairs([{@id_1, @id_2}, {@id_1, @id_3}])}
      end

      {news, _told} =
        reread(pot(%{Label => [@id_3], Project => [@id_1]}), Label, rows, read_pairs)

      assert_received {:read_pairs, %{Label => [@id_2, @id_3]}}

      assert news.edges == [
               edge(:add_relationship, Project, @id_1, "labels", @id_2),
               edge(:del_relationship, Project, @id_1, "labels", @id_3)
             ]
    end

    # Neither is held before the reread, so each stays in the other's set only when sets are judged
    # by what the client holds after it.
    test "hands over rows naming each other with each other in their sets" do
      rows = [
        %Module30{id: @id_1, follows: [%Module30{id: @id_2}]},
        %Module30{id: @id_2, follows: [%Module30{id: @id_1}]}
      ]

      {news, _told} = reread(Pot.new(), Module30, rows, fn _ids -> %{} end)

      assert [
               %Module30{id: @id_1, follows: [%Module30{id: @id_2}]},
               %Module30{id: @id_2, follows: [%Module30{id: @id_1}]}
             ] = news.appeared
    end

    test "reads no pairs when nothing is handed over or dropped" do
      rows = [%Label{id: @id_2}]

      {news, _told} =
        reread(pot(%{Label => [@id_2]}), Label, rows, fn _ids -> flunk("read pairs") end)

      assert news == %{appeared: [], edges: [], hidden: [], patched: [], unsynced: []}
    end

    test "hands a row over with its sets holding only the rows the client holds" do
      rows = [%Project{id: @id_1, labels: [%Label{id: @id_2}, %Label{id: @id_3}], public: true}]

      {news, _told} = reread(pot(%{Label => [@id_3]}), Project, rows, fn _ids -> %{} end)

      assert [%Project{labels: [%Label{id: @id_3}]}] = news.appeared
    end
  end

  describe "reread/5" do
    test "hands every row read over when held isn't trusted" do
      rows = [%Label{id: @id_2}]

      {news, _told} =
        reread(pot(%{Label => [@id_2]}), Label, rows, fn _ids -> %{} end, trust_held?: false)

      assert Enum.map(news.appeared, & &1.id) == [@id_2]
    end
  end

  describe "verdict_rows/2" do
    test "returns the held rows the part carries verdicts of, each with them" do
      held_project = %Project{id: @id_1, public: true}
      new_project = %Project{id: @id_2, public: true}

      part =
        part(
          readable: [held_project, new_project],
          unreadable: %{Project => [@id_3]},
          verdicts: %{Project => %{@id_1 => %{"archive" => true}, @id_2 => %{"archive" => false}}}
        )

      assert verdict_rows(pot(%{Project => [@id_1, @id_3]}), part) == [
               {held_project, %{"archive" => true}}
             ]
    end
  end
end
