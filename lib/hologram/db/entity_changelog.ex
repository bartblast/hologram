defmodule Hologram.DB.EntityChangelog do
  @moduledoc false

  # The entity changelog: one row per entity-level effect, appended in the transaction that
  # caused it, so a write and the record of it either both land or neither does. What the
  # rows are read for is which entity types and attributes a transaction touched - the values
  # a client is sent come from reading the rows themselves afresh, never from here. That is
  # what lets the log store a write WHOLE, server-only values included: what may be shown is
  # decided where a row meets the wire, against the model of the moment, rather than by what
  # was stored years earlier.

  alias Hologram.Auth.Context
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model
  alias Hologram.Mutation.Ref

  @channel "hologram_outbox"

  @columns [
    "op",
    "type",
    "entity_id",
    "data",
    "model_hash",
    "actor_id",
    "revisions",
    "mutation_ref"
  ]

  @data_ops [:del_entity, :patch_entity, :put_entity]

  @relationship_ops [:add_relationship, :del_relationship]

  @doc """
  Appends the given effects to the log in the caller's transaction, and wakes the dispatchers
  listening for them. Appending nothing does nothing.

  An effect names its `:op`, the `:entity_type` and `:entity_id` it happened to, and what the op
  carries: `:data` for `:put_entity` (every attribute), `:patch_entity` (the changed ones) and
  `:del_entity` (every attribute the row held when it was removed), `:relationship` and
  `:target_id` for the relationship ops.

  A put says what a row became and a delete says what it was, so a row that is gone stays
  readable for as long as the log keeps its entry.

  An effect of a create or an update carries the `:revisions` it set - the stamp per column, keyed
  by field - which is stored beside it. An edge or a delete carries none.

  Every value the write set is stored, values of server_only attributes included: the log is kept
  for good, and what an attribute is allowed to show is a fact about the model NOW, which the wire
  applies when a row reaches it. Nothing reads a value from here to send it - the readers below
  take the KEYS, to know what moved. The acting user is read from the ambient context, so writes
  made by the framework itself, which have no actor, record none.

  The batch of client writes being applied is read from the ambient context the same way, and an
  effect written outside one records none - a command's write, a seed's, the framework's own. It
  is what lets a client tell the effects of its own writes apart from everyone else's when they
  arrive on the stream.
  """
  @spec append(list(map)) :: :ok
  def append([]), do: :ok

  # sobelow_skip ["SQL.Query"]
  def append(effects) do
    model_hash = Model.hash()
    actor_id = Codec.encode(Context.actor_user_id(), :uuid)
    mutation_ref = Ref.get()

    values = Enum.flat_map(effects, &row(&1, model_hash, actor_id, mutation_ref))

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

  What it answers is whether a returning client's place is one the log can speak for. Every effect
  since the log was created is still here, so the only place older than this one is a cursor from
  before it existed - and what such a client missed cannot be told, which leaves sending it
  everything as the one honest answer.
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
  Returns at most `limit` effects written after the given place, in the order a reader is told
  about them.

  The order is the windowed read's own - by transaction, then by insert order within it - so a
  place names the same point for a returning client as it did for a connected one. Everything here
  is committed, which is why this read needs no upper edge: gap-freeness is the windowed read's
  problem, and history has no gaps left to open.

  The limit is not a page - nothing here resumes from where it stopped. It is what keeps a reader
  from pulling an unbounded tail into memory, and a caller that gets `limit` rows back should treat
  the gap as too big to replay rather than as all of it.

  **`data` is not read.** History is used as an index of ids: it says which rows moved, and the
  values come from reading those rows as they now stand. Leaving the payload behind is what makes
  an effect here a FIXED size, so a count is an honest bound on what a gap costs to hold - a wide
  entity's `put_entity` carries several times a narrow one's, and a reader that fetched it could
  not tell from the count how much memory it had asked for.

  Effects arrive flat rather than grouped, for the same reason.
  """
  @spec read_after(non_neg_integer, non_neg_integer, pos_integer) :: list(map)
  def read_after(tx, seq, limit) do
    statement = """
    SELECT "seq", "op", "type", "entity_id", "tx", "model_hash", "actor_id", "revisions",
           "mutation_ref"
    FROM "hologram_system"."outbox"
    WHERE "tx" > $1 OR ("tx" = $1 AND "seq" > $2)
    ORDER BY "tx", "seq"
    LIMIT $3
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [tx, seq, limit])

    Enum.map(rows, &place_event/1)
  end

  @doc """
  Returns the entity the given stored data describes - the inverse of what `append/1` writes, so a
  row read back out of the log is the struct it was.

  Every value is decoded against the type its declaration gives, which is what the encoding used
  on the way in. A key the type does not declare raises: a payload is written by this build for
  this build, and a gap spanning a change of model is refused before anything reads one.

  The metadata is the type's own default - the stamps a row carried are recorded beside the data
  rather than in it, and a row rebuilt from a delete has none to carry.
  """
  @spec entity_from_data(module, map) :: struct
  def entity_from_data(entity_type, data) do
    fields =
      Enum.map(data, fn {name, value} ->
        field = String.to_existing_atom(name)

        {:ok, decoded} = Codec.decode_json(value, attribute_type(entity_type, field))

        {field, decoded}
      end)

    struct!(entity_type, fields)
  end

  @doc """
  Returns the effects written to rows of the given entity type since the given place, whose stored
  data holds every pair of `data_match` - in place order, and carrying the data each was written
  with. An empty match takes every effect of the type.

  What one type's rows have been through since a place, where `read_after/3` answers WHICH rows
  moved across every type. The payload is read here, which `read_after/3` deliberately does not
  do: this exists for a caller reconstructing what a small, insert-and-delete-only type held, and
  the values are the whole point of asking.

  Deliberately unlimited. It is read for a gap whose size has already been decided, over the same
  range - so it can answer no more rows than that gap holds, and a limit here would be a second
  bound on a thing already bounded.

  An op or entity type this node does not know stays the label it was written with, exactly as
  `read_window/2` leaves it.
  """
  @spec read_type_after(module, non_neg_integer, non_neg_integer, map) :: list(map)
  def read_type_after(entity_type, tx, seq, data_match) do
    statement = """
    SELECT "seq", "op", "type", "entity_id", "data", "tx", "model_hash", "actor_id", "revisions",
           "mutation_ref"
    FROM "hologram_system"."outbox"
    WHERE "type" = $1
      AND ("tx" > $2 OR ("tx" = $2 AND "seq" > $3))
      AND "data" @> $4::jsonb
    ORDER BY "tx", "seq"
    """

    params = [Codec.encode_enum_value(entity_type), tx, seq, data_match]

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, params)

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
  stay strings, as do the revisions' keys, because a peer running a newer build can write names
  this node has never heard of - names that match nothing here, which is exactly what they should
  do.
  """
  @spec read_window(non_neg_integer, non_neg_integer) :: list({non_neg_integer, list(map)})
  def read_window(last_xmin, current_xmin) do
    statement = """
    SELECT "seq", "op", "type", "entity_id", "data", "tx", "model_hash", "actor_id", "revisions",
           "mutation_ref"
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
    Map.new(data, fn {name, value} ->
      {name, Codec.encode_json(value, attribute_type(entity_type, name))}
    end)
  end

  defp data(%{op: op, relationship: relationship, target_id: target_id})
       when op in @relationship_ops do
    %{relationship: relationship, target_id: target_id}
  end

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

  # The history read's shape: everything the windowed read gives except the payload, which nothing
  # replaying it looks at. Fixed size by construction, which is what lets its caller bound a gap by
  # counting - the batch a write belongs to is bookkeeping of a bounded size, where the payload is
  # the part that runs from a delete's nothing to a wide entity's kilobytes.
  defp place_event([seq, op, type, entity_id, tx, model_hash, actor_id, revisions, mutation_ref]) do
    %{
      actor_id: Codec.decode(actor_id, :uuid),
      entity_id: Codec.decode(entity_id, :uuid),
      model_hash: model_hash,
      mutation_ref: mutation_ref,
      op: operation(op),
      revisions: revisions,
      seq: seq,
      tx: tx,
      type: entity_type(type)
    }
  end

  defp event([seq, op, type, entity_id, data, tx, model_hash, actor_id, revisions, mutation_ref]) do
    %{
      actor_id: Codec.decode(actor_id, :uuid),
      data: data,
      entity_id: Codec.decode(entity_id, :uuid),
      model_hash: model_hash,
      mutation_ref: mutation_ref,
      op: operation(op),
      revisions: revisions,
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
         actor_id,
         mutation_ref
       ) do
    [
      Atom.to_string(op),
      Codec.encode_enum_value(entity_type),
      Codec.encode(entity_id, :uuid),
      data(effect),
      model_hash,
      actor_id,
      Map.get(effect, :revisions),
      mutation_ref
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
