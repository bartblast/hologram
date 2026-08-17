defmodule Hologram.Sync.DiffTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Diff

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1

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
    Module2
    |> Entity.new(a: true, c: title)
    |> DB.create()
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
  end

  describe "deltas/4 - edges" do
    defp edge_events(entity_id, op, relationship, target_id) do
      data = %{"relationship" => relationship, "target_id" => target_id}

      [{200, [%{op: op, type: Module3, entity_id: entity_id, data: data}]}]
    end

    defp source_with_targets(target_ids) do
      required =
        Module1
        |> Entity.new()
        |> DB.create()

      source =
        Module3
        |> Entity.new(c_id: required.id)
        |> DB.create()

      Enum.each(target_ids, &DB.add_relationship(Module3, source.id, :a, &1))

      %{source | a: Enum.map(target_ids, &DB.get(Module2, &1))}
    end

    test "reports an edge the round says is there" do
      target = row("target")
      source = source_with_targets([target.id])
      events = edge_events(source.id, :add_relationship, "a", target.id)

      deltas = deltas(result([source]), MapSet.new([source.id]), nil, events)

      assert deltas.edges == [
               %{
                 entity_id: source.id,
                 op: :add_relationship,
                 relationship: "a",
                 target_id: target.id
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
        Module14
        |> Entity.new(email: "edge_reader@example.com")
        |> DB.create()

      hidden =
        PolicyModule1
        |> Entity.new()
        |> DB.create()

      events = edge_events(hidden.id, :add_relationship, "a", Entity.generate_id())

      deltas = deltas(result([hidden]), MapSet.new([hidden.id]), user.id, events)

      assert deltas.edges == []
    end

    # The row carries no field of that name at all, which is what a window embedding no such
    # relationship looks like from here - there is nothing to say the edge moved WITHIN.
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
  end

  describe "deltas/4 - visibility" do
    setup do
      user =
        Module14
        |> Entity.new(email: "reader@example.com")
        |> DB.create()

      %{user: user}
    end

    test "leaves out a row this client may not read", %{user: user} do
      hidden =
        PolicyModule1
        |> Entity.new()
        |> DB.create()

      refute Auth.can?(user.id, :read, hidden)

      deltas = deltas(result([hidden]), MapSet.new(), user.id, [])

      assert deltas.appeared == []
    end

    test "returns a row this client may read", %{user: user} do
      readable =
        PolicyModule1
        |> Entity.new(public: true)
        |> DB.create()

      deltas = deltas(result([readable]), MapSet.new(), user.id, [])

      assert deltas.appeared == [readable]
    end

    test "reports a row the client holds but may no longer read as vanished", %{user: user} do
      hidden =
        PolicyModule1
        |> Entity.new()
        |> DB.create()

      deltas = deltas(result([hidden]), MapSet.new([hidden.id]), user.id, [])

      assert deltas.vanished == [hidden.id]
      assert deltas.patched == []
    end

    test "tells two clients different things about one round", %{user: user} do
      public_row =
        PolicyModule1
        |> Entity.new(priority: 1, public: true)
        |> DB.create()

      granted_row =
        PolicyModule1
        |> Entity.new(priority: 2)
        |> DB.create()

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
