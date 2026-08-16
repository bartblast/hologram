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

  @doc """
  Returns the cursor naming the given place in the log.
  """
  @spec encode(non_neg_integer, non_neg_integer) :: String.t()
  def encode(tx, seq) do
    Base.url_encode64("#{tx}.#{seq}", padding: false)
  end

  @doc """
  Returns the place the given cursor names, or `:error` for one this build cannot read.
  """
  @spec decode(term) :: {:ok, non_neg_integer, non_neg_integer} | :error
  def decode(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [tx, seq] <- String.split(decoded, "."),
         {tx, ""} <- Integer.parse(tx),
         {seq, ""} <- Integer.parse(seq),
         true <- tx >= 0 and seq >= 0 do
      {:ok, tx, seq}
    else
      _unreadable -> :error
    end
  end

  def decode(_not_a_cursor), do: :error
end
