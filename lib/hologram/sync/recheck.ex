defmodule Hologram.Sync.Recheck do
  @moduledoc false

  # Who may read the rows a batch of changes touched, decided for every user with a sync session
  # on this node at once: one statement per entity type, whatever the number of users, each
  # returning the rows' current values beside their readers and the server's verdicts for them. A
  # rule or a deciding clause answering the same for every user is decided once per row, and the
  # rest test each user as the acting user (see Hologram.DB.QueryCompiler.recheck/4).
  #
  # The values are read fresh here, never taken from the changes, so a row goes out as it is now.

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.QueryCache
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity
  alias Hologram.Policy

  @type readers :: :all | MapSet.t(String.t() | nil)

  @type verdicts :: %{
          anonymous: %{String.t() => boolean} | nil,
          others: %{String.t() => boolean} | nil,
          users: %{String.t() => %{String.t() => boolean}}
        }

  @doc """
  Returns, per entity type, every row of the given ids that one of the given users may read, keyed
  by id, with the row's current values, its readers and its verdicts. The readers are `:all` when
  every user may read it, anonymous ones included, and otherwise the set of the given users who may
  - nil among them when an anonymous user may. The verdicts are the server's answers on the type's
  deciding clauses for those readers, which `verdicts/2` gives per reader - none when the build has
  no client checking permissions, which never reads one, as `Hologram.Sync.Frame.row_verdicts/2`
  answers.

  Takes the ids to check per entity type, as canonical entity ids, and the users as ids, nil for an
  anonymous one - a user id in any other spelling reads as an anonymous one. An id is left out
  when its row is gone or none of the given users may read it, so a caller holding it reads that as
  "may read: no". A type with no ids, and a call with no users, run nothing and are left out of the
  result. Each type is its own statement, so two types see the same commits only inside one
  transaction.
  """
  @spec run(%{module => Enumerable.t()}, list(any)) ::
          %{module => %{Entity.id() => {struct, readers, verdicts}}}
  def run(_rows_to_check, []), do: %{}

  def run(rows_to_check, user_ids) do
    mapping = DB.mapping()

    # Asked only when a type has something to answer, as Frame.row_verdicts/2 asks.
    verdicts? =
      Enum.any?(rows_to_check, fn {entity_type, ids} ->
        not Enum.empty?(ids) and Policy.deciding_quantifiers(entity_type) != []
      end) and QueryCache.permission_checking?()

    for {entity_type, ids} <- rows_to_check, not Enum.empty?(ids), into: %{} do
      {entity_type, QueryRunner.recheck(entity_type, mapping, ids, user_ids, verdicts?)}
    end
  end

  @doc """
  Returns whether the given readers include the given user - nil for an anonymous one, and for a
  user id in any spelling but the one Hologram generates, which names no user entity.
  """
  @spec reads?(readers, any) :: boolean
  def reads?(:all, _user_id), do: true

  def reads?(readers, user_id), do: MapSet.member?(readers, Auth.canonical_id(user_id))

  @doc """
  Returns the given user's verdicts among the given ones, a row's from `run/2`, keyed by verdict key
  - what `Hologram.Sync.Frame.row_verdicts/2` answers for the user and the row. Takes nil for an
  anonymous user, and a user id in any spelling but the one Hologram generates reads as an anonymous
  one.

  Only a reader of the row given to `run/2` may be asked: a signed-in user left out of the call is
  given what a reader no anchor names answers, which needn't be theirs. Raises for an anonymous
  user when none was given, and for a signed-in one the statement had to test but didn't.
  """
  @spec verdicts(verdicts, any) :: %{String.t() => boolean}
  def verdicts(verdicts, user_id) do
    answers =
      case Auth.canonical_id(user_id) do
        nil -> verdicts.anonymous
        canonical_id -> Map.get(verdicts.users, canonical_id, verdicts.others)
      end

    answers ||
      raise ArgumentError,
            "no verdicts for #{inspect(user_id)}, who wasn't given to the recheck as a reader"
  end
end
