defmodule Hologram.Sync.Catchup do
  @moduledoc false

  # What a client that comes back missed while it was away - or why it cannot be told, and has to
  # be sent everything again.
  #
  # Replaying the gap costs what CHANGED while the client was away. Sending everything again costs
  # what it HOLDS. A client away for five minutes holding forty rows is told about the two that
  # moved, which is why the gap is the routine and the resync is the fallback.
  #
  # Four doors lead to that fallback, and each is a thing that cannot usefully be answered rather
  # than a thing that went wrong: a place that cannot be read, a place predating the log, a gap
  # too big to be worth replaying, and a gap spanning a change of model. All of them are decided
  # before a single ROW is looked at - the effects name which rows to read, and none is read here.
  #
  # A grant given or taken away while the client was gone is the one change the gap cannot speak
  # of: it moves one row and changes what the client may see of many, which no effect names. So
  # the gap comes back with the grants as they stood at the client's place beside it, for the
  # session to judge its rows under both and say what moved between them.

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Oplog
  alias Hologram.Entity.Model
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Frame

  # The most effects a replay will carry, and past it the client is sent everything instead.
  #
  # A COUNT is an honest bound here only because the history read leaves the payload behind: an
  # effect it returns is 31 words whatever the row was, where one carrying `data` runs from 33 for
  # a delete to 337 for a wide entity's put - a tenfold spread a count cannot see. The connection
  # process reads the gap and is killed at a million words, so 5,000 of them is 1.2 MB against a
  # 7 MB cap, a sixth of it, and that fraction does not move with what the app stores.
  #
  # The economics set the ceiling rather than the memory does, which is why the number is thousands
  # and not tens of thousands: a replay re-reads every row it names, so by a few thousand touched
  # rows it already costs what a resync costs, and unlike a resync it is unbounded. Where between
  # those the line falls is the policy part - the per-effect size and the kill threshold are not.
  @default_gap_limit 5_000

  # How many rows one frame carries. A frame holds whole rows rather than the log's fixed-size
  # entries, so its cost moves with what the app stores - 500 wide rows is megabytes where 500
  # narrow ones is kilobytes, which is why this is smaller than the gap limit by an order of
  # magnitude rather than equal to it. Policy: it trades frames-per-fill against bytes-per-frame,
  # and neither end is dangerous.
  @default_rows_per_frame 500

  @doc """
  Returns the most effects a replay will carry.
  """
  @spec gap_limit() :: pos_integer
  def gap_limit do
    :hologram
    |> Application.get_env(:sync, [])
    |> Keyword.get(:gap_limit, @default_gap_limit)
  end

  @doc """
  Returns how many rows one frame carries.

  A frame is built, encoded and written whole, so this is what bounds the memory any single one
  costs - and on a replay it is also the granularity a cut-off client resumes at.
  """
  @spec rows_per_frame() :: pos_integer
  def rows_per_frame do
    :hologram
    |> Application.get_env(:sync, [])
    |> Keyword.get(:rows_per_frame, @default_rows_per_frame)
  end

  @doc """
  Returns what to tell a returning client about the rows the given gap touched, given the `pot` it
  may see now - the rows of every window it holds, keyed by id, already checked against who it is.

  A row the gap touched and the pot still holds is handed over WHOLE and as it now stands, not as
  the log said it was: the log names which rows to go and look at, and looking is what supplies
  the values. One that the pot no longer holds is one the client may no longer see.

  A row touched many times while the client was away is spoken of once - it has one current state,
  however many times it got there.

  Nothing is said about a type this build has never compiled: a peer running a newer model can
  write names this build has never heard of, and a client of this build has nowhere to put them.
  """
  @spec deltas(list(map), map) :: list(map)
  def deltas(effects, pot) do
    effects
    |> Enum.filter(&is_atom(&1.type))
    |> Enum.uniq_by(& &1.entity_id)
    |> Enum.map(&delta(&1, pot))
  end

  @doc """
  Returns the effects written since the given cursor and the grants the given actor held at it,
  or why everything must be sent again.

  What comes back names WHICH rows moved, never what they now hold - the values come from reading
  those rows as they stand. That is what makes the log safe to read as history: its order is not
  commit order, so folding it would build a past that never happened, while using it as an index
  of ids cannot.

  The grants are nil unless the gap holds a change to this actor's own, which is the only case a
  row nothing touched can have changed hands in. Nil for an anonymous client too: no grant names
  it, so nothing about it can have moved.
  """
  @spec gap(term, String.t() | nil) ::
          {:ok, list(map), list(struct) | nil} | {:full_resync, atom}
  def gap(cursor, actor_user_id) do
    with {:ok, tx, seq} <- decode_place(cursor),
         :ok <- check_retention(tx, seq),
         {:ok, effects} <- read_gap(tx, seq) do
      {:ok, effects, grants_then(effects, tx, seq, actor_user_id)}
    end
  end

  defp read_gap(tx, seq) do
    tx
    |> Oplog.read_after(seq, gap_limit() + 1)
    |> check_size()
  end

  # Read one past the limit, so "too many" is answered without holding them all: the extra row is
  # the only evidence needed that the gap does not fit.
  defp check_size(effects) do
    if length(effects) > gap_limit() do
      {:full_resync, :gap_too_large}
    else
      check_model(effects)
    end
  end

  # A gap spanning a deploy is refused whole rather than in part: the client's bundle reads rows of
  # one model, and half a replay would hand it rows of two.
  defp check_model(effects) do
    model_hash = Model.hash()

    if Enum.all?(effects, &(&1.model_hash == model_hash)) do
      {:ok, effects}
    else
      {:full_resync, :model_hash}
    end
  end

  # Asked only when the gap holds a grant effect at all, which is a walk of what is already in
  # memory - an ordinary resume reads nothing extra. Asked AFTER the model door, so every effect
  # here is this build's own and a type compares as the module it is rather than as a label a
  # newer peer wrote.
  #
  # A gap holding grants that are all somebody else's answers nil the same way an empty one does:
  # what another user may see is not this client's business, and no rule grants by a grant held
  # by somebody else.
  defp grants_then(_effects, _tx, _seq, nil), do: nil

  defp grants_then(effects, tx, seq, actor_user_id) do
    if Enum.any?(effects, &(&1.type == RoleGrant)) do
      case Oplog.read_type_after(RoleGrant, tx, seq, %{"user_id" => actor_user_id}) do
        [] -> nil
        grant_effects -> Auth.grants_before(actor_user_id, grant_effects)
      end
    end
  end

  # The cursor came from a frame, so the effect it names was written. If the oldest effect still
  # held is NEWER than that, the cursor predates the log and what it names cannot be told. If the
  # oldest is at or below it, the log speaks for the whole gap.
  #
  # A log holding nothing cannot say either way, so it says the honest thing.
  defp check_retention(tx, seq) do
    case Oplog.oldest_place() do
      nil -> {:full_resync, :retention}
      oldest when oldest <= {tx, seq} -> :ok
      _predates_log -> {:full_resync, :retention}
    end
  end

  # A row that is gone and a row that is merely out of reach are both told as `unsync_entity`, the
  # same as the connected path tells them. Telling them apart would mean asking whether a row the
  # client may not read exists at all, which answers a question it was not allowed to ask.
  # TODO: offline mutations need the distinction (a queued write against a deleted row is a
  # rejection, against an unsynced one it is fine) - it arrives with them, from the effect's own op
  # rather than from an existence check.
  defp delta(effect, pot) do
    case Map.fetch(pot, effect.entity_id) do
      {:ok, row} -> Frame.put_entity(row)
      :error -> Frame.unsync_entity(effect.entity_id, effect.type)
    end
  end

  defp decode_place(cursor) do
    case Cursor.decode(cursor) do
      {:ok, tx, seq} -> {:ok, tx, seq}
      :error -> {:full_resync, :cursor}
    end
  end
end
