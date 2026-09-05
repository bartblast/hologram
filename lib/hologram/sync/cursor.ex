defmodule Hologram.Sync.Cursor do
  @moduledoc false

  # Where a client got to in the oplog, as a string it stores and hands back without reading.
  # Opaque by convention, not by secrecy: what a place is made of can change without the protocol
  # changing because the client never interprets one, not because it could not. Nothing here hides
  # the place or depends on its being hidden.
  #
  # Decoding treats it as what it is - a string a client sends - so it is parsed rather than
  # trusted. A forged one costs nothing: replaying from the wrong place reads rows that are
  # checked against the asker anyway, and a place the log no longer reaches is answered by
  # sending everything again.
  #
  # Costing nothing depends on the place being one the LOG COULD HOLD, which is why the numbers are
  # bounded rather than merely non-negative. Elixir integers have no ceiling and the log's columns
  # do, so a place above theirs reaches the driver as a value it cannot encode - and the read that
  # would have answered "send everything again" raises instead, on a connection whose 200 has
  # already gone out.

  # What the log's own columns hold: `tx` is an xid8, `seq` a bigserial. A place beyond either is
  # one no row could carry, so it is unreadable in the only sense that matters.
  @max_seq 9_223_372_036_854_775_807
  @max_tx 18_446_744_073_709_551_615

  @doc """
  Returns the cursor naming the given place in the log.
  """
  @spec encode(non_neg_integer, non_neg_integer) :: String.t()
  def encode(tx, seq) do
    "#{tx}.#{seq}"
  end

  @doc """
  Returns the place the given cursor names, or `:error` for one this build cannot read - which
  includes a place no row of the log could carry, since the columns it would be compared against
  have ceilings and an Elixir integer does not.
  """
  @spec decode(term) :: {:ok, non_neg_integer, non_neg_integer} | :error
  def decode(cursor) when is_binary(cursor) do
    with [tx, seq] <- String.split(cursor, "."),
         {tx, ""} <- Integer.parse(tx),
         {seq, ""} <- Integer.parse(seq),
         true <- in_range?(tx, @max_tx) and in_range?(seq, @max_seq) do
      {:ok, tx, seq}
    else
      _unreadable -> :error
    end
  end

  def decode(_not_a_cursor), do: :error

  defp in_range?(value, ceiling), do: value >= 0 and value <= ceiling
end
