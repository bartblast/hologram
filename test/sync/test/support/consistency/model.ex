defmodule HologramSyncTests.Consistency.Model do
  @moduledoc false

  # What each user may read in a state of the test's tables, worked out from the read rules
  # written again in Elixir rather than asked of Hologram - the oracle the consistency checks
  # compare the simulated clients against. `model_test.exs` keeps it honest: for a state with every
  # rule's branches, it answers what Hologram's own reads answer.
  #
  # A state holds rows as the wire carries them - each row's declared attributes and reference
  # ids, keyed by their names as strings, with ids, strings and booleans as JSON has them - so a
  # client's store compares with it directly.

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.Query
  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Notice
  alias HologramSyncTests.Entities.NoticeBlock
  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.SpaceMember
  alias HologramSyncTests.Entities.Tag
  alias HologramSyncTests.Entities.User

  @types [Board, Card, Notice, NoticeBlock, Space, SpaceMember, Tag, User]

  # The to-many relationships a row travels with as a set of ids, by type: a card's tags, and the
  # inverse of that on a tag. Every other relationship is a to-one, whose reference field is the
  # row's, or the inverse of one, which travels as the other rows' reference fields.
  @sets %{Card => %{"tags" => Tag}, Tag => %{"cards" => Card}}

  @typedoc """
  A state of the test's tables: the rows of each type by id, the card and tag pairs, and the
  viewer grants on boards, each `{user_id, board_id}`, or `{user_id, :all}` for a type-wide one.
  """
  @type state :: %{
          grants: MapSet.t({String.t(), String.t() | :all}),
          pairs: MapSet.t({String.t(), String.t()}),
          rows: %{module => %{String.t() => map}}
        }

  @doc """
  Returns the rows of each type the given user may read in the given state, keyed by id, each with
  its fields and, for a card and a tag, the ids of the other side of their pairs it may read, sorted
  - what a client of the user holds once it's caught up. Nil is an anonymous session.
  """
  @spec expected(state, String.t() | nil) :: %{module => %{String.t() => map}}
  def expected(state, user_id) do
    Map.new(@types, fn type ->
      rows =
        for {id, fields} <- Map.fetch!(state.rows, type),
            readable?(state, user_id, type, id),
            into: %{},
            do: {id, Map.merge(fields, sets(state, user_id, type, id))}

      {type, rows}
    end)
  end

  @doc """
  Returns the declared fields a row of the given type travels with, as the wire names them, sorted:
  its attributes and the reference field of each to-one relationship.
  """
  @spec fields(module) :: list(String.t())
  def fields(type) do
    attributes =
      Enum.map(type.__attributes__(), fn {name, _type, _opts} -> Atom.to_string(name) end)

    references =
      for {name, target, _opts} <- type.__relationships__(), is_atom(target), do: "#{name}_id"

    Enum.sort(attributes ++ references)
  end

  @doc """
  Returns whether the given user may read the row of the given type with the given id in the given
  state, by the read rules of the type. Nil is an anonymous session, which reads tags alone: every
  other rule names the acting user, and a `none` naming it is false without one.
  """
  @spec readable?(state, String.t() | nil, module, String.t()) :: boolean
  def readable?(state, user_id, type, id) do
    rows = Map.fetch!(state.rows, type)

    case Map.fetch(rows, id) do
      {:ok, row} -> readable_row?(state, user_id, type, id, row)
      :error -> false
    end
  end

  @doc """
  Returns the current state of the test's tables. Read with the server's own authority, so every
  row is read whoever is acting, and in a statement per type, one for the pairs and one for the
  grants - a caller wanting one moment reads it where no write can commit in between.
  """
  @spec snapshot() :: state
  def snapshot do
    rows =
      Map.new(@types, fn type ->
        rows =
          type
          |> read_all()
          |> Map.new(&{&1.id, wire_fields(type, &1)})

        {type, rows}
      end)

    %{rows: pairs} =
      DB.sql!(~s(SELECT "source_id", "target_id" FROM "hologram_data"."#{tags_table()}"))

    grants =
      for %{entity_type: Board, role: :viewer} = grant <- read_all(RoleGrant),
          into: MapSet.new(),
          do: {grant.user_id, grant.entity_id || :all}

    %{grants: grants, pairs: MapSet.new(pairs, &List.to_tuple/1), rows: rows}
  end

  @doc """
  Returns the sets a row of the given type travels with, by name, each with the type of the rows it
  names.
  """
  @spec sets(module) :: %{String.t() => module}
  def sets(type), do: Map.get(@sets, type, %{})

  @doc """
  Returns the entity types the test syncs, sorted.
  """
  @spec types() :: list(module)
  def types, do: Enum.sort(@types)

  defp member?(state, space_id, user_id) do
    state.rows
    |> Map.fetch!(SpaceMember)
    |> Enum.any?(fn {_id, member} ->
      member["space_id"] == space_id and member["user_id"] == user_id
    end)
  end

  defp readable_row?(_state, _user_id, Tag, _id, _row), do: true

  defp readable_row?(_state, nil, _type, _id, _row), do: false

  defp readable_row?(state, user_id, Board, id, row) do
    MapSet.member?(state.grants, {user_id, id}) or MapSet.member?(state.grants, {user_id, :all}) or
      (row["archived"] == false and member?(state, row["space_id"], user_id))
  end

  defp readable_row?(state, user_id, Card, _id, row) do
    readable?(state, user_id, Board, row["board_id"])
  end

  defp readable_row?(state, user_id, Notice, id, _row) do
    state.rows
    |> Map.fetch!(NoticeBlock)
    |> Enum.all?(fn {_id, block} -> block["notice_id"] != id or block["user_id"] != user_id end)
  end

  defp readable_row?(state, user_id, Space, id, _row), do: member?(state, id, user_id)

  defp readable_row?(_state, user_id, User, id, _row), do: id == user_id

  defp readable_row?(_state, user_id, type, _id, row) when type in [NoticeBlock, SpaceMember] do
    row["user_id"] == user_id
  end

  # A card's tags and a tag's cards, kept to the ones the user may read, as the fill keeps a set.
  defp sets(state, user_id, type, id) do
    type
    |> sets()
    |> Map.new(fn {name, target_type} ->
      named =
        state.pairs
        |> Enum.map(&other_side(type, &1, id))
        |> Enum.reject(&is_nil/1)

      {name, set_ids(state, user_id, target_type, named)}
    end)
  end

  defp other_side(Card, {id, tag_id}, id), do: tag_id

  defp other_side(Tag, {card_id, id}, id), do: card_id

  defp other_side(_type, _pair, _id), do: nil

  defp set_ids(state, user_id, type, ids) do
    ids
    |> Enum.filter(&readable?(state, user_id, type, &1))
    |> Enum.sort()
  end

  defp read_all(type) do
    type
    |> Query.trust()
    |> DB.read()
  end

  defp tags_table, do: DB.join_table_name(Card, :tags)

  defp wire_fields(type, entity) do
    type
    |> fields()
    |> Map.new(&{&1, Map.fetch!(entity, String.to_existing_atom(&1))})
  end
end
