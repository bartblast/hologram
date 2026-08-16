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

  defp decode_place(cursor) do
    case Cursor.decode(cursor) do
      {:ok, tx, seq} -> {:ok, tx, seq}
      :error -> {:full_resync, :cursor}
    end
  end
end
