defmodule Hologram.DB.Outbox do
  @moduledoc false

  # The effect log: one row per entity-level effect, appended in the transaction that caused it,
  # so a write and the record of it either both land or neither does. What the rows are read for
  # is which entity types and attributes a transaction touched - the values a client is sent come
  # from reading the rows themselves afresh, never from here.

  alias Hologram.Auth.Context
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Model

  @channel "hologram_outbox"

  @columns ["op", "type", "entity_id", "data", "model_hash", "actor_id"]

  @data_ops [:patch_entity, :put_entity]

  # Pruning is one job over a log every node shares, so one node does it and the rest find the
  # lock held. Arbitrary, but it must never move once deployed, or two builds mid-rollout would
  # prune past each other.
  @prune_lock_key 0x484F_4C4F

  @relationship_ops [:add_relationship, :del_relationship]

  @doc """
  Appends the given effects to the outbox in the caller's transaction, and wakes the dispatchers
  listening for them. Appending nothing does nothing.

  An effect names its `:op`, the `:entity_type` and `:entity_id` it happened to, and what the op
  carries: `:data` for `:put_entity` (every attribute) and `:patch_entity` (the changed ones),
  `:relationship` and `:target_id` for the relationship ops, nothing for `:del_entity`.

  Values of attributes declared server_only are dropped rather than stored - the log outlives the
  transaction by as long as its retention window, and nothing in it may hold what never leaves
  the server. The acting user is read from the ambient context, so writes made by the framework
  itself, which have no actor, record none.
  """
  @spec append(list(map)) :: :ok
  def append([]), do: :ok

  # sobelow_skip ["SQL.Query"]
  def append(effects) do
    model_hash = Model.hash()
    actor_id = Codec.encode(Context.actor_user_id(), :uuid)

    values = Enum.flat_map(effects, &row(&1, model_hash, actor_id))

    column_list = Enum.map_join(@columns, ", ", &Mapper.quote_identifier/1)
    row_list = row_placeholders(length(effects))

    statement =
      "INSERT INTO #{qualified_table()} (#{column_list}) VALUES #{row_list}"

    {:ok, _result} = Connection.query(statement, values)

    notify()
  end

  @doc """
  Returns the channel an append announces itself on, which is the one a listener waits on - the
  two cannot drift apart while they read it from here.
  """
  @spec channel() :: String.t()
  def channel, do: @channel

  @doc """
  Returns the transaction id below which every transaction has finished - the upper edge of the
  next window to read.

  A transaction takes its id when it first writes, and holds it until it commits or aborts, so
  this value cannot pass one that is still open. That is what makes the windows gap-free: a row
  written by a transaction still in flight sits above this edge and waits for a later window,
  rather than being passed over because a later-numbered row committed first.
  """
  @spec current_xmin() :: non_neg_integer
  def current_xmin do
    {:ok, %Postgrex.Result{rows: [[xmin]]}} =
      Connection.query("SELECT pg_snapshot_xmin(pg_current_snapshot())")

    xmin
  end

  @doc """
  Returns the place of the oldest effect the log still holds, or nil when it holds none.

  What it answers is whether a returning client's place is still covered: the log is pruned from
  the front, so a place older than this one has had effects taken from under it and what the
  client missed can no longer be told - the only honest answer left is to send it everything.
  """
  @spec oldest_place() :: {non_neg_integer, non_neg_integer} | nil
  def oldest_place do
    statement = """
    SELECT "tx", "seq"
    FROM "hologram_system"."outbox"
    ORDER BY "tx", "seq"
    LIMIT 1
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    case rows do
      [[tx, seq]] -> {tx, seq}
      [] -> nil
    end
  end

  @doc """
  Removes the effects written more than `older_than_seconds` ago, and returns how many went.

  What this bounds is REPLAY REACH and nothing else: a client returning to a place the log no
  longer covers is sent everything instead of the little it missed. It cannot make an answer
  wrong, only expensive - `oldest_place/0` works out whether a place is still covered from the
  log as it stands, never from whatever this was last called with.

  One node prunes per round and the rest remove nothing, which is what the advisory lock in the
  statement is for. It is TRANSACTION-scoped and taken inside the delete's own statement, so it
  is held for exactly as long as the delete and released whatever becomes of it - a session-scoped
  lock taken and released as two statements would travel over two POOLED connections, and one left
  behind on a connection nobody closes is a log no node may ever prune again.
  """
  @spec prune(non_neg_integer) :: non_neg_integer
  def prune(older_than_seconds) do
    statement = """
    DELETE FROM "hologram_system"."outbox"
    WHERE "inserted_at" < now() - make_interval(secs => $1::double precision)
      AND (SELECT pg_try_advisory_xact_lock($2))
    """

    {:ok, %Postgrex.Result{num_rows: num_rows}} =
      Connection.query(statement, [older_than_seconds, @prune_lock_key])

    num_rows
  end

  @doc """
  Returns at most `limit` effects written after the given place, in the order a reader is told
  about them.

  The order is the windowed read's own - by transaction, then by insert order within it - so a
  place names the same point for a returning client as it did for a connected one. Everything here
  is committed, which is why this read needs no upper edge: gap-freeness is the windowed read's
  problem, and history has no gaps left to open.

  The limit is not a page - nothing here resumes from where it stopped. It is what keeps a reader
  from pulling an unbounded tail into memory, and a caller that gets `limit` rows back should treat
  the gap as too big to replay rather than as all of it.

  Effects arrive flat rather than grouped, because what a reader wants of them is which rows to go
  and look at - the values come from those rows, never from here.
  """
  @spec read_after(non_neg_integer, non_neg_integer, pos_integer) :: list(map)
  def read_after(tx, seq, limit) do
    statement = """
    SELECT "seq", "op", "type", "entity_id", "data", "tx", "model_hash", "actor_id"
    FROM "hologram_system"."outbox"
    WHERE "tx" > $1 OR ("tx" = $1 AND "seq" > $2)
    ORDER BY "tx", "seq"
    LIMIT $3
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [tx, seq, limit])

    Enum.map(rows, &event/1)
  end

  @doc """
  Returns the effects written by transactions from `last_xmin` up to but excluding `current_xmin`,
  grouped into `{transaction id, effects}` pairs and ordered by transaction and then by insert
  order, so a transaction's effects arrive together and in the order they happened.

  The order across transactions is stable but is NOT commit order - a transaction that committed
  later can carry a smaller id. Nothing may materialize state by folding these in order: they say
  which entity types and attributes a transaction touched, and a reader wanting values reads the
  rows themselves.

  An op or entity type this node does not know stays the label it was written with, and data keys
  stay strings, because a peer running a newer build can write names this node has
  never heard of - names that match nothing here, which is exactly what they should do.
  """
  @spec read_window(non_neg_integer, non_neg_integer) :: list({non_neg_integer, list(map)})
  def read_window(last_xmin, current_xmin) do
    statement = """
    SELECT "seq", "op", "type", "entity_id", "data", "tx", "model_hash", "actor_id"
    FROM "hologram_system"."outbox"
    WHERE "tx" >= $1 AND "tx" < $2
    ORDER BY "tx", "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [last_xmin, current_xmin])

    rows
    |> Enum.map(&event/1)
    |> Enum.chunk_by(& &1.tx)
    |> Enum.map(fn [%{tx: tx} | _rest] = events -> {tx, events} end)
  end

  defp attribute_type(entity_type, name) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    case Enum.find(definitions, fn {definition_name, _type, _opts} -> definition_name == name end) do
      # A name matching no attribute definition is a to-one reference field, and every reference
      # column carries the entity id type.
      nil -> :uuid
      {_name, type, _opts} -> type
    end
  end

  defp data(%{op: op, entity_type: entity_type, data: data}) when op in @data_ops do
    server_only = Entity.server_only_attribute_names(entity_type)

    data
    |> Map.drop(server_only)
    |> Map.new(fn {name, value} ->
      {name, Codec.encode_json(value, attribute_type(entity_type, name))}
    end)
  end

  defp data(%{op: op, relationship: relationship, target_id: target_id})
       when op in @relationship_ops do
    %{relationship: relationship, target_id: target_id}
  end

  defp data(%{op: :del_entity}), do: nil

  defp entity_type(label) do
    String.to_existing_atom("Elixir." <> label)
  rescue
    ArgumentError -> label
  end

  # An op this build does not know stays the label it was written with, the same as an entity type
  # it has never compiled. A newer peer writing a seventh op is a thing a rolling deploy produces,
  # and raising here would take the dispatcher down mid-window - it restarts with no cursor and
  # resumes at the log's edge, so everything between would be skipped rather than retried.
  defp operation(label) do
    String.to_existing_atom(label)
  rescue
    ArgumentError -> label
  end

  defp event([seq, op, type, entity_id, data, tx, model_hash, actor_id]) do
    %{
      actor_id: Codec.decode(actor_id, :uuid),
      data: data,
      entity_id: Codec.decode(entity_id, :uuid),
      model_hash: model_hash,
      op: operation(op),
      seq: seq,
      tx: tx,
      type: entity_type(type)
    }
  end

  defp notify do
    {:ok, _result} = Connection.query("SELECT pg_notify($1, '')", [@channel])

    :ok
  end

  defp qualified_table do
    "#{Mapper.quote_identifier("hologram_system")}.#{Mapper.quote_identifier("outbox")}"
  end

  defp row(
         %{op: op, entity_type: entity_type, entity_id: entity_id} = effect,
         model_hash,
         actor_id
       ) do
    [
      Atom.to_string(op),
      Codec.encode_enum_value(entity_type),
      Codec.encode(entity_id, :uuid),
      data(effect),
      model_hash,
      actor_id
    ]
  end

  defp row_placeholders(count) do
    column_count = length(@columns)

    Enum.map_join(0..(count - 1), ", ", fn index ->
      placeholders =
        Enum.map_join(1..column_count, ", ", &"$#{index * column_count + &1}")

      "(#{placeholders})"
    end)
  end
end
