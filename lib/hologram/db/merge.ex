defmodule Hologram.DB.Merge do
  @moduledoc false

  # The per-column rule a write authored elsewhere is applied under: a column whose revision the
  # writer saw unchanged is set, a column that moved since is decided by comparing the write's
  # stamp to the revision the row now holds - the newer EDIT wins, not the later arrival - and a
  # column the write does not name is not its business, so two writers editing different columns
  # of one row never contend at all.
  #
  # Pure, and it reads nothing but its arguments: the client runs the same rule when it re-applies
  # a pending write over a frame that arrived meanwhile, and both tiers have to reach the same
  # answer for the local view to match what the server stored.

  @doc """
  Returns the given changes that win against the given stored revisions, and the names of the columns that lost, sorted.

  A column wins when the writer saw the revision the row still holds - what the write says it was
  based on equals what is stored - or when the write's stamp is above that revision. It loses when
  the row holds a revision at or above the stamp, which is an edit newer than this one.

  A column named by neither map reads as revision 0: never set by anyone, so nothing can have moved
  under the writer.
  """
  @spec resolve(%{atom => any}, %{atom => pos_integer}, pos_integer, %{atom => pos_integer}) ::
          {%{atom => any}, list(atom)}
  def resolve(changes, based_on, stamp, stored) do
    {winners, losers} =
      Enum.split_with(changes, fn {name, _value} -> wins?(name, based_on, stamp, stored) end)

    lost_names =
      losers
      |> Enum.map(fn {name, _value} -> name end)
      |> Enum.sort()

    {Map.new(winners), lost_names}
  end

  @doc """
  Returns :delete when a write with the given stamp wins against every revision the row holds, and :drop when any column moved past it.

  A delete takes every column of a row with it, so unlike an update it cannot land on part of one:
  it goes through when each column was either seen unchanged or is older than the write, and is
  dropped whole otherwise. A row holding no revisions at all has nothing that could have moved.
  """
  @spec resolve_delete(%{atom => pos_integer}, pos_integer, %{atom => pos_integer}) ::
          :delete | :drop
  def resolve_delete(based_on, stamp, stored) do
    if Enum.all?(stored, fn {name, _revision} -> wins?(name, based_on, stamp, stored) end) do
      :delete
    else
      :drop
    end
  end

  # The stamp has to be strictly above the stored revision for the write to win on that half: an
  # equal one is another writer's edit at the same moment, and letting it through would make the
  # answer depend on which of the two arrived last, which is what comparing stamps exists to avoid.
  defp wins?(name, based_on, stamp, stored) do
    stored_revision = Map.get(stored, name, 0)

    Map.get(based_on, name, 0) == stored_revision or stamp > stored_revision
  end
end
