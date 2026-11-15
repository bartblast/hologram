defmodule Hologram.Sync.Recheck do
  @moduledoc false

  # Who may read the rows a batch of changes touched, decided for every user with a sync session
  # on this node at once: one statement per entity type, whatever the number of users, each
  # returning the rows' current values beside their readers. A rule answering the same for every
  # user is decided once per row, and the rest test each user as the acting user (see
  # Hologram.DB.QueryCompiler.recheck/3).
  #
  # The values are read fresh here, never taken from the changes, so a row goes out as it is now.

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity

  @type readers :: :all | MapSet.t(String.t() | nil)

  @doc """
  Returns, per entity type, every row of the given ids that one of the given users may read, keyed
  by id, with the row's current values and its readers: `:all` when every user may read it,
  anonymous ones included, and otherwise the set of the given users who may - nil among them when
  an anonymous user may.

  Takes the ids to check per entity type, as canonical entity ids, and the users as ids, nil for an
  anonymous one - a user id in any other spelling reads as an anonymous one. An id is left out
  when its row is gone or none of the given users may read it, so a caller holding it reads that as
  "may read: no". A type with no ids, and a call with no users, run nothing and are left out of the
  result. Each type is its own statement, so two types see the same commits only inside one
  transaction.
  """
  @spec run(%{module => Enumerable.t()}, list(any)) ::
          %{module => %{Entity.id() => {struct, readers}}}
  def run(_rows_to_check, []), do: %{}

  def run(rows_to_check, user_ids) do
    mapping = DB.mapping()

    for {entity_type, ids} <- rows_to_check, not Enum.empty?(ids), into: %{} do
      {entity_type, QueryRunner.recheck(entity_type, mapping, ids, user_ids)}
    end
  end

  @doc """
  Returns whether the given readers include the given user - nil for an anonymous one, and for a
  user id in any spelling but the one Hologram generates, which names no user entity.
  """
  @spec reads?(readers, any) :: boolean
  def reads?(:all, _user_id), do: true

  def reads?(readers, user_id), do: MapSet.member?(readers, Auth.canonical_id(user_id))
end
