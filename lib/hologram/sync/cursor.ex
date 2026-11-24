defmodule Hologram.Sync.Cursor do
  @moduledoc false

  # Where a client got to in the oplog, in which log, under which rules and with which entity types
  # synced, as a string it stores and hands back without reading. The place is an entry's seq, with
  # its transaction and the time it was written, which tell it from another entry given the same seq
  # after the server lost the first's commit. The log id tells this log from one a dropped database
  # was claimed again with, whose serials start over. The rules ride along because a deploy can
  # change them without moving a row: what a client holds at a place is what those rules let it
  # see, not what the current ones do. The types ride along for the same reason - a deploy that
  # starts syncing a type moves no row of it, and a client filled before holds none.
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

  # What the log's own columns hold: `tx` is an xid8, `seq` a bigint, the time a timestamptz read as
  # microseconds, which fits a bigint. A place beyond any is one no row could carry, so it is
  # unreadable in the only sense that matters.
  alias Hologram.Commons.CryptographicUtils
  alias Hologram.DB.Codec
  alias Hologram.DB.Oplog

  @max_bigint 9_223_372_036_854_775_807
  @max_tx 18_446_744_073_709_551_615

  @doc """
  Returns the cursor naming the given place (see `Hologram.DB.Oplog.place/1`) in the log with the
  given id (see `Hologram.DB.Oplog.log_id/0`), under the rules with the given policy hash
  (see `Hologram.Policy.hash/1`) - the rules the rows a client holds there were judged by - and
  with the given types hash (see `types_hash/3`), naming the entity types sync sends and the model
  the rows were read under. A place is only worth resuming from under the rules that decided what
  it holds, with the types it was filled with, under the model it was filled under.
  """
  @spec encode(Oplog.place(), String.t(), String.t(), String.t()) :: String.t()
  def encode({seq, tx, inserted_at}, log_id, policy_hash, types_hash) when is_binary(log_id) do
    "#{seq}.#{tx}.#{inserted_at}.#{log_id}.#{policy_hash}.#{types_hash}"
  end

  @doc """
  Returns the place the given cursor names, the id of the log it is in, the policy hash it was
  judged under and the types hash it was filled with, or `:error` for one this build cannot read -
  which includes a place no row of the log could carry, since the columns it would be compared
  against have ceilings and an Elixir integer does not, and a cursor naming no log, no rules or no
  types, as one written before cursors named them does.
  """
  @spec decode(term) :: {:ok, Oplog.place(), String.t(), String.t(), String.t()} | :error
  def decode(cursor) when is_binary(cursor) do
    with [seq, tx, inserted_at, log_id, policy_hash, types_hash] <- String.split(cursor, "."),
         {seq, ""} <- Integer.parse(seq),
         {tx, ""} <- Integer.parse(tx),
         {inserted_at, ""} <- Integer.parse(inserted_at),
         true <- in_range?(seq, @max_bigint) and in_range?(tx, @max_tx),
         true <- in_range?(inserted_at, @max_bigint),
         true <- String.match?(log_id, ~r/\A[0-9a-f]{32}\z/),
         true <- hex?(policy_hash) and hex?(types_hash) do
      {:ok, {seq, tx, inserted_at}, log_id, policy_hash, types_hash}
    else
      _unreadable -> :error
    end
  end

  def decode(_not_a_cursor), do: :error

  @doc """
  Returns the hash a cursor names the given entity types by - the types sync sends (see
  `Hologram.DB.QueryCache.synced_types/0`) - whether the browser checks permissions (see
  `Hologram.DB.QueryCache.permission_checking?/0`), and the hash of the data model the rows were
  read under (see `Hologram.Entity.Model.hash/0`), as the same short digest the policy hash is.
  The types' order moves nothing.

  Whether the browser checks permissions is in it because the rows a client holds carry the server's
  verdicts only when it does (see `Hologram.Sync.Frame.row_verdicts/2`): a client filled without
  them holds rows with none, and nothing in the log says so - a deploy turning the checks on moves
  no row. A place naming the other answer sends the client everything again, like a place filled
  with other types.

  The model is in it because a migration can change rows at rest with nothing in the log to say so
  - a column made required takes a value in every row that held none - and a tab built against an
  older model keeps across the deploy the rows it was filled with. A client of the current model
  never names a place from another: its store is one per model hash.
  """
  @spec types_hash(list(module), boolean, String.t()) :: String.t()
  def types_hash(entity_types, permission_checking?, model_hash) do
    labels =
      entity_types
      |> Enum.map(&Codec.encode_enum_value/1)
      |> Enum.sort()
      |> Enum.join(",")

    checks = if permission_checking?, do: ";checks", else: ""

    CryptographicUtils.short_digest(labels <> checks <> ";" <> model_hash, 16)
  end

  defp in_range?(value, ceiling), do: value >= 0 and value <= ceiling

  defp hex?(hash), do: String.match?(hash, ~r/\A[0-9a-f]+\z/)
end
