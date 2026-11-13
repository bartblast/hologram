defmodule Hologram.Sync.Cursor do
  @moduledoc false

  # Where a client got to in the oplog, and under which rules, as a string it stores and hands back
  # without reading. The rules ride along because a deploy can change them without moving a row:
  # what a client holds at a place is what those rules let it see, not what the current ones do.
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
  Returns the cursor naming the given place in the log, under the rules with the given policy hash
  (see `Hologram.Policy.hash/1`) - the rules the rows a client holds there were judged by. A place
  is only worth resuming from under the rules that decided what it holds.
  """
  @spec encode(non_neg_integer, non_neg_integer, String.t()) :: String.t()
  def encode(tx, seq, policy_hash) do
    "#{tx}.#{seq}.#{policy_hash}"
  end

  @doc """
  Returns the place the given cursor names and the policy hash it was judged under, or `:error` for
  one this build cannot read - which includes a place no row of the log could carry, since the
  columns it would be compared against have ceilings and an Elixir integer does not, and a cursor
  naming no rules, as one written before cursors named them does.
  """
  @spec decode(term) :: {:ok, non_neg_integer, non_neg_integer, String.t()} | :error
  def decode(cursor) when is_binary(cursor) do
    with [tx, seq, policy_hash] <- String.split(cursor, "."),
         {tx, ""} <- Integer.parse(tx),
         {seq, ""} <- Integer.parse(seq),
         true <- in_range?(tx, @max_tx) and in_range?(seq, @max_seq),
         true <- policy_hash?(policy_hash) do
      {:ok, tx, seq, policy_hash}
    else
      _unreadable -> :error
    end
  end

  def decode(_not_a_cursor), do: :error

  defp in_range?(value, ceiling), do: value >= 0 and value <= ceiling

  defp policy_hash?(policy_hash), do: String.match?(policy_hash, ~r/\A[0-9a-f]+\z/)
end
