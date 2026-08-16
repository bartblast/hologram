defmodule Hologram.Sync.DiffTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Diff

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
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
        |> Entity.new(public: true)
        |> DB.create()

      private_row =
        PolicyModule1
        |> Entity.new()
        |> DB.create()

      round = result([public_row, private_row])

      reader_deltas = deltas(round, MapSet.new(), user.id, [])
      trusted_deltas = deltas(round, MapSet.new(), nil, [])

      assert reader_deltas.appeared == [public_row]
      assert Enum.sort_by(trusted_deltas.appeared, & &1.id) == Enum.sort_by([public_row], & &1.id)
    end
  end
end
