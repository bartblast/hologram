defmodule HologramSyncTests.Helpers do
  @moduledoc false

  import Hologram.Query, only: [add_relationship: 3]

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Notice
  alias HologramSyncTests.Entities.NoticeBlock
  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.SpaceMember
  alias HologramSyncTests.Entities.Tag
  alias HologramSyncTests.Entities.User

  @doc """
  Creates a row of the given type with the given fields, as trusted code, and returns it.
  """
  @spec create!(module, keyword | map) :: struct
  def create!(type, fields) do
    fields
    |> Map.new()
    |> type.new()
    |> DB.create!()
  end

  @doc """
  Truncates every entity table of the app, the join table behind a card's tags and the role grant
  store, in one statement - PostgreSQL refuses to truncate a table another one references without
  it.

  The simulated clients sync the whole app, so a row an earlier test left in any of them would
  arrive in the next test's fill.
  """
  @spec truncate_tables() :: :ok
  def truncate_tables do
    tables =
      Model.types()
      |> Enum.concat([RoleGrant])
      |> Enum.map(&DB.table_name/1)
      |> Enum.concat([DB.join_table_name(Card, :tags)])
      |> Enum.map_join(", ", &~s("hologram_data"."#{&1}"))

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  @doc """
  Writes a state taking every read rule's branches and returns its users: a member of one space
  and not the other, a viewer on an archived board of that space, a type-wide viewer, and a user
  in no space at all - with a notice blocking the member, and tags on cards of boards some users
  read and others don't.
  """
  @spec write_fixture() :: list(struct)
  def write_fixture do
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

    [member, viewer, wide_viewer, outsider]
  end
end
