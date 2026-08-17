defmodule Hologram.Sync.Cursor do
  @moduledoc false

  # Where a client got to in the effect log, in a form it keeps and hands back without reading.
  # Being opaque is the point: what it is made of is the reader's business, so the shape can
  # change without the protocol changing.
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
    Base.url_encode64("#{tx}.#{seq}", padding: false)
  end

  @doc """
  Returns the place the given cursor names, or `:error` for one this build cannot read - which
  includes a place no row of the log could carry, since the columns it would be compared against
  have ceilings and an Elixir integer does not.
  """
  @spec decode(term) :: {:ok, non_neg_integer, non_neg_integer} | :error
  def decode(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [tx, seq] <- String.split(decoded, "."),
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
