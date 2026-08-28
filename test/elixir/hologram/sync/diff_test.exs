defmodule Hologram.Sync.DiffTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Query, only: [add_relationship: 3]
  import Hologram.Sync.Diff

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyModule3

  defp events(entity_id, names) do
    data = Map.new(names, &{&1, "whatever the log said"})

    [{200, [%{op: :patch_entity, type: Module2, entity_id: entity_id, data: data}]}]
  end

  defp result(rows) do
    by_id = Map.new(rows, &{&1.id, &1})

    ids =
      by_id
      |> Map.keys()
      |> MapSet.new()

    %{ids: ids, rows: by_id}
  end

  defp row(title) do
    %{a: true, c: title}
    |> Module2.new()
    |> DB.create!()
  end

  defp source_with_targets(targets) do
    required = DB.create!(Module1.new())

    source =
      %{c_id: required.id}
      |> Module3.new()
      |> DB.create!()

    Enum.each(targets, fn target ->
      source
      |> add_relationship(:a, target.id)
      |> DB.update()
    end)

    %{source | a: targets}
  end

  describe "deltas/4 - appeared" do
    test "returns a row the client does not hold" do
      task = row("first")

      deltas = deltas(result([task]), MapSet.new(), nil, [])

      assert deltas.appeared == [task]
    end

    test "returns nothing for a row the client already holds" do
      task = row("first")

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, [])

      assert deltas.appeared == []
    end

    test "returns every row on a first round" do
      first = row("first")
      second = row("second")

      deltas = deltas(result([first, second]), MapSet.new(), nil, [])

      assert Enum.sort_by(deltas.appeared, & &1.c) == [first, second]
    end

    # An edge added to a parent the client already holds must deliver the child's row alongside
    # the pair - an edge naming a row the client does not have would be a fact about nothing.
    test "returns the row of a child newly embedded under an already-held parent" do
      target = row("joined later")
      source = source_with_targets([target])
      events = edge_events(source.id, :add_relationship, "a", target.id)

      deltas = deltas(result([source]), MapSet.new([source.id]), nil, events)

      assert deltas.appeared == [target]
      assert [%{op: :add_relationship}] = deltas.edges
    end
  end

  describe "deltas/4 - patched" do
    test "returns the attributes the effects named, valued from the round" do
      task = row("current value")

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, events(task.id, ["c"]))

      assert deltas.patched == [{task, %{c: "current value"}}]
    end

    test "values a patch from the round rather than from the effect that named it" do
      task = row("current value")

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, events(task.id, ["c"]))

      assert [{_row, patch}] = deltas.patched
      refute patch.c == "whatever the log said"
    end

    test "returns nothing for a row no effect named" do
      task = row("first")

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, events("other-id", ["c"]))

      assert deltas.patched == []
    end

    test "returns nothing for a row the client does not hold" do
      task = row("first")

      deltas = deltas(result([task]), MapSet.new(), nil, events(task.id, ["c"]))

      assert deltas.patched == []
      assert deltas.appeared == [task]
    end

    test "passes over an attribute the row does not have" do
      task = row("first")
      transactions = events(task.id, ["c", "never_compiled"])

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, transactions)

      assert deltas.patched == [{task, %{c: "first"}}]
    end

    test "gathers what several effects named for one row" do
      task = row("first")

      transactions = [
        {200, [%{op: :patch_entity, type: Module2, entity_id: task.id, data: %{"c" => "x"}}]},
        {201, [%{op: :patch_entity, type: Module2, entity_id: task.id, data: %{"a" => false}}]}
      ]

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, transactions)

      assert deltas.patched == [{task, %{a: true, c: "first"}}]
    end

    test "returns a patch for a row held only through an include" do
      target = row("current value")
      source = source_with_targets([target])
      held = MapSet.new([source.id, target.id])

      deltas = deltas(result([source]), held, nil, events(target.id, ["c"]))

      assert deltas.patched == [{target, %{c: "current value"}}]
    end

    test "returns a patch for a row embedded beneath another embedded row" do
      author =
        %{email: "author@example.com"}
        |> Module14.new()
        |> DB.create!()

      child =
        %{author_id: author.id, public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      parent = DB.create!(PolicyModule3.new())

      round_parent = %{parent | children: [%{child | author: author}]}
      held = MapSet.new([parent.id, child.id, author.id])

      transactions = [
        {200,
         [
           %{
             op: :patch_entity,
             type: Module14,
             entity_id: author.id,
             data: %{"email" => "whatever the log said"}
           }
         ]}
      ]

      deltas = deltas(result([round_parent]), held, author.id, transactions)

      assert deltas.patched == [{author, %{email: "author@example.com"}}]
    end
  end

  describe "deltas/4 - edges" do
    defp edge_events(entity_id, op, relationship, target_id) do
      data = %{"relationship" => relationship, "target_id" => target_id}

      [{200, [%{op: op, type: Module3, entity_id: entity_id, data: data}]}]
    end

    test "reports an edge the round says is there" do
      target = row("target")
      source = source_with_targets([target])
      events = edge_events(source.id, :add_relationship, "a", target.id)

      deltas = deltas(result([source]), MapSet.new([source.id]), nil, events)

      assert deltas.edges == [
               %{
                 entity_id: source.id,
                 op: :add_relationship,
                 relationship: "a",
                 target_id: target.id,
                 type: Module3
               }
             ]
    end

    test "reports an edge the round says is gone" do
      target = row("target")
      source = source_with_targets([])
      events = edge_events(source.id, :del_relationship, "a", target.id)

      deltas = deltas(result([source]), MapSet.new([source.id]), nil, events)

      assert [%{op: :del_relationship, target_id: target_id}] = deltas.edges
      assert target_id == target.id
    end

    # Two effects moving one edge arrive in an order that is stable rather than the order they
    # committed, so what the round holds now is the only trustworthy answer.
    test "reports what the round holds when effects added and removed one edge" do
      target = row("target")
      source = source_with_targets([])

      events = [
        {200,
         [
           %{
             op: :add_relationship,
             type: Module3,
             entity_id: source.id,
             data: %{"relationship" => "a", "target_id" => target.id}
           },
           %{
             op: :del_relationship,
             type: Module3,
             entity_id: source.id,
             data: %{"relationship" => "a", "target_id" => target.id}
           }
         ]}
      ]

      deltas = deltas(result([source]), MapSet.new([source.id]), nil, events)

      assert [%{op: :del_relationship}] = deltas.edges
    end

    test "reports nothing for a row this client cannot see" do
      user =
        %{email: "edge_reader@example.com"}
        |> Module14.new()
        |> DB.create!()

      hidden = DB.create!(PolicyModule1.new())

      events = edge_events(hidden.id, :add_relationship, "a", Entity.generate_id())

      deltas = deltas(result([hidden]), MapSet.new([hidden.id]), user.id, events)

      assert deltas.edges == []
    end

    # The row carries no field of that name at all, which is what a window embedding no such
    # relationship looks like from here - there is nothing to say the edge moved WITHIN.
    # An added edge names its target the way an embedded list does, so it is withheld on the same
    # terms - here the parent goes out with its list emptied, and the edge would have named the
    # very row that emptying withheld.
    test "reports nothing for a target this client cannot see" do
      hidden = DB.create!(PolicyModule1.new())

      parent = DB.create!(PolicyModule3.new())

      round_parent = %{parent | children: [hidden]}

      events = [
        {200,
         [
           %{
             op: :add_relationship,
             type: PolicyModule3,
             entity_id: parent.id,
             data: %{"relationship" => "children", "target_id" => hidden.id}
           }
         ]}
      ]

      deltas = deltas(result([round_parent]), MapSet.new(), nil, events)

      assert deltas.appeared == [%{parent | children: []}]
      assert deltas.edges == []
    end

    test "reports nothing for a relationship the window does not embed" do
      task = row("no embeds here")

      events =
        edge_events(task.id, :add_relationship, "not_embedded", Entity.generate_id())

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, events)

      assert deltas.edges == []
    end

    # The other way a round can hold no list for a name: the row carries the field, and it is an
    # attribute rather than an embedded relationship. Separate from the case above because they
    # reach the same silence by different routes, and only one of them survives a change to what
    # an unembedded name answers with.
    test "reports nothing for a name the row carries as an attribute" do
      task = row("an attribute, not an edge")
      events = edge_events(task.id, :add_relationship, "a", Entity.generate_id())

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, events)

      assert deltas.edges == []
    end

    # What makes a frame's deltas safe to apply in any order: the edge and the row that travels
    # beside it are read from the same round, so they cannot say different things about the same
    # pair. The put states the whole target set, the edge states one pair of it, and here both
    # name the target.
    test "agrees with the row the same round hands over" do
      target = row("target")
      source = source_with_targets([target])
      events = edge_events(source.id, :add_relationship, "a", target.id)

      deltas = deltas(result([source]), MapSet.new(), nil, events)

      appeared_source = Enum.find(deltas.appeared, &(&1.id == source.id))

      assert Enum.map(appeared_source.a, & &1.id) == [target.id]

      assert [%{op: :add_relationship, target_id: target_id}] = deltas.edges
      assert target_id == target.id
    end

    test "reports nothing when no effect touched an edge" do
      task = row("first")

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, events(task.id, ["c"]))

      assert deltas.edges == []
    end
  end

  describe "deltas/4 - vanished" do
    test "returns an id the round no longer holds" do
      task = row("first")

      deltas = deltas(result([]), MapSet.new([task.id]), nil, [])

      assert deltas.vanished == [task.id]
    end

    test "returns nothing while the round still holds the id" do
      task = row("first")

      deltas = deltas(result([task]), MapSet.new([task.id]), nil, [])

      assert deltas.vanished == []
    end

    test "returns the id of a row the round no longer embeds" do
      target = row("target")
      source = source_with_targets([])

      deltas = deltas(result([source]), MapSet.new([source.id, target.id]), nil, [])

      assert deltas.vanished == [target.id]
    end

    test "returns nothing while the round still embeds the row" do
      target = row("target")
      source = source_with_targets([target])

      deltas = deltas(result([source]), MapSet.new([source.id, target.id]), nil, [])

      assert deltas.vanished == []
    end
  end

  describe "deltas/4 - visibility" do
    setup do
      user =
        %{email: "reader@example.com"}
        |> Module14.new()
        |> DB.create!()

      %{user: user}
    end

    test "leaves out a row this client may not read", %{user: user} do
      hidden = DB.create!(PolicyModule1.new())

      refute Auth.can?(user.id, :read, hidden)

      deltas = deltas(result([hidden]), MapSet.new(), user.id, [])

      assert deltas.appeared == []
    end

    test "leaves out an embedded row this client may not read", %{user: user} do
      hidden = DB.create!(PolicyModule1.new())

      parent = DB.create!(PolicyModule3.new())

      round_parent = %{parent | children: [hidden]}

      refute Auth.can?(user.id, :read, hidden)

      deltas = deltas(result([round_parent]), MapSet.new(), user.id, [])

      # Scrubbed, not merely withheld: the parent goes out with the unreadable member filtered
      # from its list, so no id list names a row this client was not given.
      assert deltas.appeared == [%{parent | children: []}]
    end

    test "scrubs each client's embedded lists to what it may see", %{user: user} do
      public_child =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      gated_child = DB.create!(PolicyModule1.new())

      Auth.grant_role(user, gated_child, :viewer)

      parent = DB.create!(PolicyModule3.new())

      round = result([%{parent | children: [public_child, gated_child]}])

      reader_deltas = deltas(round, MapSet.new(), user.id, [])
      anonymous_deltas = deltas(round, MapSet.new(), nil, [])

      reader_parent = Enum.find(reader_deltas.appeared, &(&1.id == parent.id))
      anonymous_parent = Enum.find(anonymous_deltas.appeared, &(&1.id == parent.id))

      assert reader_parent == %{parent | children: [public_child, gated_child]}
      assert anonymous_parent == %{parent | children: [public_child]}
    end

    test "returns a row this client may read", %{user: user} do
      readable =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      deltas = deltas(result([readable]), MapSet.new(), user.id, [])

      assert deltas.appeared == [readable]
    end

    test "reports a row the client holds but may no longer read as vanished", %{user: user} do
      hidden = DB.create!(PolicyModule1.new())

      deltas = deltas(result([hidden]), MapSet.new([hidden.id]), user.id, [])

      assert deltas.vanished == [hidden.id]
      assert deltas.patched == []
    end

    test "tells two clients different things about one round", %{user: user} do
      public_row =
        %{priority: 1, public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      granted_row =
        %{priority: 2}
        |> PolicyModule1.new()
        |> DB.create!()

      # What makes the two clients differ: `allow :read, to: [:viewer, ...]` opens the non-public
      # row to whoever holds the role on it, and nothing opens it to whoever holds none.
      Auth.grant_role(user, granted_row, :viewer)

      round = result([public_row, granted_row])

      reader_deltas = deltas(round, MapSet.new(), user.id, [])
      anonymous_deltas = deltas(round, MapSet.new(), nil, [])

      assert Enum.sort_by(reader_deltas.appeared, & &1.priority) == [public_row, granted_row]

      # nil means anonymous on the read side, never trusted: a visitor sees what is public and
      # nothing that a rule gates on who is asking.
      assert anonymous_deltas.appeared == [public_row]
    end
  end
end
