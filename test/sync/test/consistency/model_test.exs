defmodule HologramSyncTests.Consistency.ModelTest do
  # async: false - each test truncates the shared tables.
  use HologramSyncTests.TestCase, async: false

  import Hologram.Query, only: [include: 2]
  import Hologram.Test, only: [as_user: 2]
  import HologramSyncTests.Helpers

  alias Hologram.DB
  alias Hologram.Sync.Fill
  alias Hologram.Sync.WireData
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Tag

  setup do
    truncate_tables()

    %{users: write_fixture()}
  end

  test "a signed-in user's rows are the rows Hologram reads for them", %{users: users} do
    state = Model.snapshot()

    for user <- users, type <- Model.types() do
      expected =
        state
        |> Model.expected(user.id)
        |> Map.fetch!(type)
        |> Map.keys()
        |> Enum.sort()

      read = as_user(user, fn -> ids(DB.read(type)) end)

      assert expected == read, "#{user.name} reads other #{inspect(type)} rows"
    end
  end

  test "a signed-in user's sets are the readable ids Hologram includes for them", %{users: users} do
    state = Model.snapshot()

    queries = [{Card, :tags, include(Card, tags)}, {Tag, :cards, include(Tag, cards)}]

    for user <- users, {type, set, query} <- queries do
      expected =
        state
        |> Model.expected(user.id)
        |> Map.fetch!(type)
        |> Map.new(fn {id, row} -> {id, Map.fetch!(row, Atom.to_string(set))} end)

      read =
        as_user(user, fn ->
          query
          |> DB.read()
          |> Map.new(&{&1.id, ids(Map.fetch!(&1, set))})
        end)

      assert expected == read, "#{user.name} is given other #{inspect(type)} #{set}"
    end
  end

  # What the fill sends, as the wire spells it - each user's and an anonymous session's rows,
  # with every field and set - is what the model expects, cut only to what the model leaves out.
  test "the fill sends each user and an anonymous session what the model expects", %{
    users: users
  } do
    state = Model.snapshot()

    for user_id <- [nil | Enum.map(users, & &1.id)], type <- Model.types() do
      {rows, _applied_seq} = Fill.read(type, user_id, nil, Model.types())

      expected =
        state
        |> Model.expected(user_id)
        |> Map.fetch!(type)

      assert Map.new(rows, &{&1.id, as_wire(&1)}) == expected,
             "#{inspect(user_id)} is sent other #{inspect(type)} rows"
    end
  end

  test "the state holds every pair and grant" do
    state = Model.snapshot()

    assert MapSet.size(state.pairs) == 3
    assert MapSet.size(state.grants) == 2
    assert Enum.any?(state.grants, &match?({_user_id, :all}, &1))
  end

  # A row as a client files it, without the fields the model doesn't hold, with its sets sorted.
  defp as_wire(row) do
    row
    |> WireData.row()
    |> Jason.encode!()
    |> Jason.decode!()
    |> Map.drop(~w(id created_at server_created_at server_updated_at updated_at $revisions))
    |> Map.new(fn
      {name, ids} when is_list(ids) -> {name, Enum.sort(ids)}
      field -> field
    end)
  end

  defp ids(rows) do
    rows
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end
end
