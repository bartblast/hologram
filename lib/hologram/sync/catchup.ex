defmodule Hologram.Sync.Catchup do
  @moduledoc false

  # What a client that comes back missed while it was away - or why it cannot be told, and has to
  # be sent everything again.
  #
  # Replaying the gap costs what CHANGED while the client was away. Sending everything again costs
  # what it HOLDS. A client away for five minutes holding forty rows is told about the two that
  # moved, which is why the gap is the routine and the resync is the fallback.
  #
  # Three doors lead to that fallback, and each is a thing that cannot be answered rather than a
  # thing that went wrong: a place that cannot be read, a log pruned past that place, and a gap
  # spanning a change of model. All three are decided before a single row is looked at.

  alias Hologram.DB.Outbox
  alias Hologram.Entity.Model
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Frame

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
  Returns the effects written since the given cursor, or why everything must be sent again.

  What comes back names WHICH rows moved, never what they now hold - the values come from reading
  those rows as they stand. That is what makes the log safe to read as history: its order is not
  commit order, so folding it would build a past that never happened, while using it as an index
  of ids cannot.
  """
  @spec gap(term) :: {:ok, list(map)} | {:full_resync, atom}
  def gap(cursor) do
    with {:ok, tx, seq} <- decode_place(cursor),
         :ok <- check_retention(tx, seq) do
      check_model(Outbox.read_after(tx, seq))
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

  # The cursor came from a frame, so the effect it names was written. If the oldest effect still
  # held is NEWER than that, the log was pruned past the client and what it missed is gone. If the
  # oldest is at or below it, nothing past the client was pruned and the gap is whole.
  #
  # A log holding nothing cannot say either way, so it says the honest thing.
  defp check_retention(tx, seq) do
    case Outbox.oldest_place() do
      nil -> {:full_resync, :retention}
      oldest when oldest <= {tx, seq} -> :ok
      _pruned_past -> {:full_resync, :retention}
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
