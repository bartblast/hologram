defmodule HologramSyncTests.Consistency.ModelTest do
  # async: false - each test truncates the shared tables.
  use HologramSyncTests.TestCase, async: false

  import Hologram.Query, only: [add_relationship: 3, include: 2]
  import Hologram.Test, only: [as_user: 2]
  import HologramSyncTests.Helpers

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.Sync.Fill
  alias Hologram.Sync.WireData
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Notice
  alias HologramSyncTests.Entities.NoticeBlock
  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.SpaceMember
  alias HologramSyncTests.Entities.Tag
  alias HologramSyncTests.Entities.User

  # A state taking every rule's branches: a member of one space and not the other, an archived
  # board its space's member may not read, a viewer on one board, a type-wide viewer, a notice
  # blocking one user, tags on cards of boards some users read and others don't, and a user in no
  # space at all.
  setup do
    truncate_tables()

    [member, viewer, wide_viewer, outsider] =
      Enum.map(~w(member viewer wide_viewer outsider), &create!(User, name: &1))

    open_space = create!(Space, name: "open")
    other_space = create!(Space, name: "other")

    create!(SpaceMember, space_id: open_space.id, user_id: member.id)
    create!(SpaceMember, space_id: other_space.id, user_id: viewer.id)

    open_board = create!(Board, name: "open", space_id: open_space.id)
    archived_board = create!(Board, archived: true, name: "archived", space_id: open_space.id)
    other_board = create!(Board, name: "other", space_id: other_space.id)

    Auth.grant_role(viewer, :viewer, archived_board)
    Auth.grant_role(wide_viewer, :viewer, Board)

    [red, blue] = Enum.map(~w(red blue), &create!(Tag, name: &1))

    create!(Card, board_id: other_board.id, title: "other card")

    for {board, title, tags} <- [
          {open_board, "open card", [red, blue]},
          {archived_board, "archived card", [red]}
        ] do
      card = create!(Card, board_id: board.id, title: title)

      tags
      |> Enum.reduce(card, &add_relationship(&2, :tags, &1.id))
      |> DB.update!()
    end

    quiet = create!(Notice, title: "quiet")
    create!(Notice, title: "loud")
    create!(NoticeBlock, notice_id: quiet.id, user_id: member.id)

    %{users: [member, viewer, wide_viewer, outsider]}
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
    |> Map.drop(~w(id created_at updated_at $revisions))
    |> Map.new(fn
      {name, ids} when is_list(ids) -> {name, Enum.sort(ids)}
      field -> field
    end)
  end

  defp create!(type, fields) do
    fields
    |> Map.new()
    |> type.new()
    |> DB.create!()
  end

  defp ids(rows) do
    rows
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end
end
