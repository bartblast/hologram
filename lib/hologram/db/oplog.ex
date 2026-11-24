defmodule Hologram.DB.Oplog do
  @moduledoc false

  # The oplog: one row per entity-level effect, appended in the transaction that caused it,
  # so a write and the record of it either both land or neither does. What the rows are read for
  # is which entity types and attributes a transaction touched - the values a client is sent come
  # from reading the rows themselves afresh, never from here. That is what lets the log store a
  # write WHOLE, server-only values included: what may be shown is decided where a row meets the
  # wire, against the model of the moment, rather than by what was stored years earlier.
  #
  # What an update's to-one references held before it is read from here too. It is never sent
  # either: it names the rows a move took the row away from, which are rows to look at again, and
  # those are read afresh like any other.

  alias Hologram.Auth.Context
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model
  alias Hologram.Mutation.Ref

  @channel "hologram_oplog"

  @columns [
    "seq",
    "op",
    "type",
    "entity_id",
    "data",
    "model_hash",
    "actor_id",
    "revisions",
    "old",
    "mutation_ref"
  ]

  @data_ops [:del_entity, :patch_entity, :put_entity]

  # PostgreSQL binds at most 65,535 parameters per statement, and each row takes one per column -
  # so a write appending more effects than that allows, like the delete of a row with thousands of
  # edges, goes in as several statements.
  @max_rows_per_insert div(65_535, length(@columns))

  # The columns every read of effects ends with, after the seq, op, type, id and data.
  @event_tail ~s|"tx", "model_hash", "actor_id", "revisions", "old", "mutation_ref", "inserted_at"|

  @relationship_ops [:add_relationship, :del_relationship]

  @type log_entry :: %{inserted_at: DateTime.t(), seq: pos_integer, tx: non_neg_integer}

  @type place :: {non_neg_integer, non_neg_integer, integer}

  # Fixed application-defined key every save holds, shared, from before it takes its first serial
  # until it ends. Frozen forever: a node reading another key would not see the saves still
  # running. Provenance (for uniqueness, not for re-derivation): first 8 bytes of
  # md5("hologram_oplog_serial") as a signed 64-bit integer.
  @serial_lock_key -7_797_217_468_688_855_007

  @doc """
  Appends the given effects to the log in the caller's transaction, and wakes the dispatchers
  listening for them. Appending nothing does nothing. A large append goes in as several statements,
  all in the caller's transaction, and wakes the dispatchers once.

  An effect names its `:op`, the `:entity_type` and `:entity_id` it happened to, and what the op
  carries: `:data` for `:put_entity` (every attribute), `:patch_entity` (the changed ones) and
  `:del_entity` (every attribute the row held when it was removed), `:relationship` and
  `:target_id` for the relationship ops.

  A put says what a row became and a delete says what it was, so a row that is gone stays
  readable for as long as the log keeps its entry.

  An effect of a create or an update carries the `:revisions` it set - the stamp per column, keyed
  by field - which is stored beside it. An edge or a delete carries none.

  An effect of a create or an update also carries the `:seq` the statement writing the row took, so
  the row's number names its entry in the log. An edge or a delete has no row number to match and
  takes a serial here.

  A `:patch_entity` may carry `:old`, the value each to-one reference it changed held before it,
  keyed by field - what points a reader at the rows the move took the row away from. An effect
  without it, which is every other op and an update changing no reference, stores none.

  Every value the write set is stored, values of server_only attributes included: the log is kept
  for good, and what an attribute is allowed to show is a fact about the model NOW, which the wire
  applies when a row reaches it. Nothing reads a value from here to send it - the readers below
  take the KEYS, to know what moved, and the old references, to know which rows to look at again.
  The acting user is read from the ambient context, so writes made by the framework itself, which
  have no actor, record none, and neither do writes under a user id no user entity can have.

  The batch of client writes being applied is read from the ambient context the same way, and an
  effect written outside one records none - a command's write, a seed's, the framework's own. It
  is what lets a client tell the effects of its own writes apart from everyone else's when they
  arrive on the stream.
  """
  @spec append(list(map)) :: :ok
  def append([]), do: :ok

  def append(effects) do
    model_hash = Model.hash()
    actor_id = Codec.encode(Context.actor_entity_id(), :uuid)
    mutation_ref = Ref.get()

    effects
    |> Enum.chunk_every(@max_rows_per_insert)
    |> Enum.each(&insert(&1, model_hash, actor_id, mutation_ref))

    notify()
  end

  @doc """
  Returns the channel an append announces itself on, which is the one a listener waits on - the
  two cannot drift apart while they read it from here.
  """
  @spec channel() :: String.t()
  def channel, do: @channel

  @doc """
  Returns the advisory lock key a save holds, shared, while it can still commit a serial.
  """
  @spec serial_lock_key() :: integer
  def serial_lock_key, do: @serial_lock_key

  @doc """
  Puts the row the server's run is read from back, after a crash or a failover emptied it. A row
  already there is left alone.

  Naming the key makes PostgreSQL refuse the insert while the key is missing, as it is during a
  restore. A row added then would collide with the restored one and leave the table with two, so
  this returns `:no_key` and adds nothing.
  """
  @spec ensure_server_run() :: :ok | :no_key
  def ensure_server_run do
    statement = """
    INSERT INTO "#{Mapper.system_schema()}"."server_run" DEFAULT VALUES
    ON CONFLICT ("only_row") DO NOTHING
    """

    case Connection.query(statement) do
      {:ok, _result} -> :ok
      {:error, %Postgrex.Error{postgres: %{code: :invalid_column_reference}}} -> :no_key
    end
  end

  @doc """
  Fills the view naming this copy of the database (see `log_id/0`) when it's empty, as a
  schema-only restore leaves it, or one that died before its last step. Reading the log id raises
  until it's filled. A view already filled is left alone, since filling it again names a new copy.
  """
  @spec populate_database_copy() :: :ok
  def populate_database_copy do
    schema = Mapper.system_schema()

    statement = """
    DO $body$
    BEGIN
      IF NOT (SELECT "relispopulated" FROM pg_catalog.pg_class
              WHERE "oid" = '"#{schema}"."database_copy"'::pg_catalog.regclass) THEN
        REFRESH MATERIALIZED VIEW "#{schema}"."database_copy";
      END IF;
    END
    $body$
    """

    {:ok, _result} = Connection.query(statement)

    :ok
  end

  @doc """
  Returns the log's entry at the given seq, or nil when it holds none, with the server run it was
  read in (see `serials_in_flight/0`).

  An entry is its seq, its transaction and the time it was written, which together tell it from a
  later entry given the same seq after the server lost the commit of the first.
  """
  @spec entry_at(non_neg_integer) :: {log_entry | nil, String.t() | nil}
  def entry_at(seq) do
    read_entry(~s|"seq" = $1|, seq)
  end

  @doc """
  Returns the log's last entry at or below the given seq, or nil when it holds none, with the server
  run it was read in (see `entry_at/1`).
  """
  @spec last_entry_through(non_neg_integer) :: {log_entry | nil, String.t() | nil}
  def last_entry_through(seq) do
    read_entry(~s|"seq" <= $1|, seq)
  end

  @doc """
  Returns the highest serial handed out so far, 0 before the first, the saves that were holding the
  serial lock right after, each named by its virtual transaction id, which tells a save from the
  next one on the same connection, and the server run both were read in, or nil when that can't be
  said.

  The serial is read first, and that order is what makes the answer safe (see
  `Hologram.Sync.FinalLimit`). A save takes the lock before its serial, so one holding a serial at
  or below the one read already held the lock, and is either among the saves read or has ended.
  Read the other way round, a save starting between the two reads would be missed.

  Postgres drops a save's lock after its commit is visible, so once a save is gone from this list a
  new read sees what it wrote.

  The run names one life of the server: the log id (see `log_id/0`), whose part a row in an
  unlogged table gives, which PostgreSQL empties after a crash and leaves empty on a promoted
  standby, and the time the server started, which a clean restart moves (see `run_log_id/1`). Each
  statement reads it itself, since one statement can't span a crash: two reads naming one run
  happened in one life of the server. Nil means the row is gone, or the two reads were in
  different runs.
  """
  @spec serials_in_flight() :: {non_neg_integer, MapSet.t(String.t()), String.t() | nil}
  def serials_in_flight do
    {high, high_run} = high_serial()
    {running, running_run} = running_saves()

    {high, running, if(high_run == running_run, do: high_run)}
  end

  @doc """
  Returns the SQL calling the function every serial comes from.
  """
  @spec next_seq_sql() :: String.t()
  def next_seq_sql, do: ~s|#{Mapper.quote_identifier(Mapper.system_schema())}."next_seq"()|

  @doc """
  Returns the highest serial handed out so far, 0 before the first. A save whose every serial is
  above it took them after this was read, so nothing read before saw what it wrote.
  """
  @spec last_serial() :: non_neg_integer
  def last_serial do
    {serial, _run} = high_serial()

    serial
  end

  @doc """
  Returns the id this log goes by, as 32 hex digits, or nil for a database with no marker or no
  server run (see `serials_in_flight/0`). A place is a place in the log only beside the id it was
  taken under.

  The id changes whenever the server may have lost commits a client was sent: a crash and a
  promoted standby name a new run, a restored dump a new copy of the database (see
  `populate_database_copy/0`), a reload of the log in place a new file for it, and a database
  dropped and claimed again, which starts its serials over, a new marker. A clean restart loses
  nothing, and keeps it. A client holds rows sent above the place it claims, so only a new id
  reaches every one that holds a lost commit, offline ones included (see `rotate_log_id/1` for a
  loss found otherwise).

  Anything else that rewrites the log's file loses nothing but changes the id too, so every client
  is sent everything again: `VACUUM FULL`, `CLUSTER`, `TRUNCATE`, a column change that rewrites the
  table, or moving it to another tablespace. So does refreshing the database copy's view by hand.
  """
  @spec log_id() :: String.t() | nil
  def log_id do
    {:ok, %Postgrex.Result{rows: [[log_id]]}} = Connection.query("SELECT #{log_id_sql()}")

    log_id
  end

  @doc """
  Gives the log a new id (see `log_id/0`), unless it has moved off the given one already. For a
  server found to have lost commits under the id it kept, so every cursor issued before the loss
  is refused. Nodes finding the same loss rotate it once between them.
  """
  @spec rotate_log_id(String.t()) :: :ok
  def rotate_log_id(log_id) do
    schema = Mapper.system_schema()

    # The marker's own column, not a read of the table it updates: every update evaluating a
    # subquery over it sees the id before any of them, so each would rotate it.
    statement = """
    UPDATE "#{schema}"."database"
    SET "log_id" = gen_random_uuid()
    WHERE #{log_id_expression(~s|"database"."log_id"|, ~s|(SELECT "run" FROM "#{schema}"."server_run")|)} = $1
    """

    {:ok, _result} = Connection.query(statement, [log_id])

    :ok
  end

  @doc """
  Returns the log id the given server run was read under (see `log_id/0`).
  """
  @spec run_log_id(String.t()) :: String.t()
  def run_log_id(run) do
    [log_id, _started_at] = String.split(run, "/")

    log_id
  end

  @doc """
  Returns whether the log holds the entry the given place names (see `place/1`), the same seq with
  the same transaction and time. The place before the log's first entry is always held. A place
  the log holds another entry at is one whose commit the server lost.
  """
  @spec holds_place?(place) :: boolean
  def holds_place?({0, 0, 0}), do: true

  def holds_place?({seq, _tx, _inserted_at} = place) do
    statement = """
    SELECT "seq", "tx", "inserted_at"
    FROM "#{Mapper.system_schema()}"."oplog"
    WHERE "seq" = $1
    """

    case Connection.query(statement, [seq]) do
      {:ok, %Postgrex.Result{rows: [[^seq, tx, inserted_at]]}} ->
        place(%{inserted_at: inserted_at, seq: seq, tx: tx}) == place

      {:ok, %Postgrex.Result{rows: []}} ->
        false
    end
  end

  @doc """
  Returns the place the given entry names: its seq, its transaction and the microsecond it was
  written at, which together tell it from a later entry given the same seq after the server lost
  the first's commit. No entry is the place before the log's first, `{0, 0, 0}`.
  """
  @spec place(log_entry | nil) :: place
  def place(nil), do: {0, 0, 0}

  def place(%{seq: seq, tx: tx, inserted_at: inserted_at}) do
    {seq, tx, DateTime.to_unix(inserted_at, :microsecond)}
  end

  @doc """
  Returns, for each replica with a batch with an effect above the given seq or in one of the given
  ranges of seqs below it, the highest sequence number among those batches - what a read after a
  batch of effects can hold of each replica's writes beyond the batch, given what was sent: every
  seq at or below the given one outside the ranges has gone out, or never will. A replica with none
  is left out. Every committed effect counts, also one above a serial a save still running holds.

  Read through the log's key like `read_unsent/2`, so it costs what was written above the given seq
  and a probe per range, not what a save holding the lowest range back has seen written since.
  """
  @spec replica_seqs_after(non_neg_integer, list({pos_integer, pos_integer})) :: %{
          String.t() => non_neg_integer
        }
  def replica_seqs_after(seq, unsent \\ []) do
    {firsts, lasts} = Enum.unzip(unsent)

    statement = """
    SELECT "mutation_ref"->>'replica_id', max(("mutation_ref"->>'seq')::bigint)
    FROM (
      SELECT "mutation_ref"
      FROM "#{Mapper.system_schema()}"."oplog"
      WHERE "seq" > $1
      UNION ALL
      SELECT "mutation_ref"
      FROM "#{Mapper.system_schema()}"."oplog"
      JOIN unnest($2::bigint[], $3::bigint[]) AS "unsent" ("first", "last")
      ON "seq" BETWEEN "unsent"."first" AND "unsent"."last"
    ) AS "unread"
    WHERE "mutation_ref" IS NOT NULL
    GROUP BY 1
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [seq, firsts, lasts])

    Map.new(rows, fn [replica_id, seq] -> {replica_id, seq} end)
  end

  @doc """
  Returns at most `limit` effects with a seq above the given one, in seq order.

  The order is the dispatcher's read's own (see `read_unsent/2`), so a place names the same point
  for a returning client as it did for a connected one. Everything here is committed, but a serial
  below an effect returned can belong to a save still running, which commits after - so a caller
  dating a place by what this returns takes the final limit before (see
  `Hologram.Sync.FinalLimit` and `Hologram.Sync.Catchup.gap/4`).

  The limit is not a page - nothing here resumes from where it stopped. It is what keeps a reader
  from pulling an unbounded tail into memory, and a caller that gets `limit` rows back should treat
  the gap as too big to replay rather than as all of it.

  **`data` is read for edges alone.** History is used as an index of ids: it says which rows
  moved, and the values come from reading those rows as they now stand. Leaving the payload behind
  is what keeps an effect here a FIXED size, so a count is an honest bound on what a gap costs to
  hold - a wide entity's `put_entity` carries several times a narrow one's, and a reader that
  fetched it could not tell from the count how much memory it had asked for. An edge's payload is
  the exception, since it names a second row that moved - the target, whose inverse of the
  relationship holds the edge too - and it is two short strings whatever the entity, so the size
  stays fixed. Every other effect comes back with `data` nil. The old references come back too, as
  the edge's payload does: an id per reference the update changed, a few at most, naming rows that
  moved as surely as the edge's target does.

  Effects arrive flat rather than grouped, so that the count stays that bound.
  """
  @spec read_after(non_neg_integer, pos_integer) :: list(map)
  def read_after(seq, limit) do
    statement = """
    SELECT "seq", "op", "type", "entity_id",
           CASE WHEN "op" IN ('add_relationship', 'del_relationship') THEN "data" END AS "data",
           #{@event_tail}
    FROM "#{Mapper.system_schema()}"."oplog"
    WHERE "seq" > $1
    ORDER BY "seq"
    LIMIT $2
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [seq, limit])

    Enum.map(rows, &event/1)
  end

  @doc """
  Returns how many effects have a seq above the given one, counting no further than `limit`,
  and whether any of the ones counted was written under a model other than the given hash's - the
  two things a returning client's resume is decided by, in one statement, with none of the effects
  read back.
  """
  @spec count_after(non_neg_integer, pos_integer, String.t()) :: {non_neg_integer, boolean}
  def count_after(seq, limit, model_hash) do
    statement = """
    SELECT count(*), coalesce(bool_or("model_hash" <> $3), false)
    FROM (
      SELECT "model_hash"
      FROM "#{Mapper.system_schema()}"."oplog"
      WHERE "seq" > $1
      ORDER BY "seq"
      LIMIT $2
    ) AS "gap"
    """

    {:ok, %Postgrex.Result{rows: [[count, other_model?]]}} =
      Connection.query(statement, [seq, limit, model_hash])

    {count, other_model?}
  end

  @doc """
  Returns the payload of each effect of the given seqs, keyed by seq, as stored: string keys, the
  values as the write encoded them. Every effect is stored with one (see `append/1`), so only a seq
  the log doesn't hold is left out.

  What `read_after/2` leaves behind, read back for a few effects at a time: a caller holding a gap
  counted without its payloads fills them in for the part of it it is working on, so it never holds
  every payload of a long gap at once.
  """
  @spec read_data(list(pos_integer)) :: %{pos_integer => map}
  def read_data([]), do: %{}

  def read_data(seqs) do
    statement = """
    SELECT "seq", "data"
    FROM "#{Mapper.system_schema()}"."oplog"
    WHERE "seq" = ANY($1::bigint[])
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [seqs])

    Map.new(rows, fn [seq, data] -> {seq, data} end)
  end

  @doc """
  Returns whether the stored data of any effect of the given seqs holds every pair of the given
  match, as `read_type_after/3` matches data - without reading any of it back. A seq the log doesn't
  hold matches nothing, and no seqs match nothing.

  For a question about a few effects of a gap of any size, answered without the payloads the gap
  read left behind: the cost follows the seqs asked about, one primary key lookup each.
  """
  @spec any_data_match?(list(pos_integer), map) :: boolean
  def any_data_match?([], _match), do: false

  def any_data_match?(seqs, match) do
    statement = """
    SELECT EXISTS (
      SELECT 1 FROM "#{Mapper.system_schema()}"."oplog"
      WHERE "seq" = ANY($1::bigint[]) AND "data" @> $2::jsonb
    )
    """

    {:ok, %Postgrex.Result{rows: [[matched?]]}} = Connection.query(statement, [seqs, match])

    matched?
  end

  @doc """
  Returns the effects written to rows of the given entity type with a seq above the given one, whose
  stored data holds every pair of `data_match` - in seq order, and carrying the data each was
  written with. An empty match takes every effect of the type.

  What one type's rows have been through since a place, where `read_after/2` answers WHICH rows
  moved across every type. The payload is read here, which `read_after/2` deliberately does not
  do: this exists for a caller reconstructing what a small, insert-and-delete-only type held, and
  the values are the whole point of asking.

  The order can't say whether a row stands now. An insert takes its serial before it waits for a
  delete of the same id, so that delete can sit above the put that outlived it.

  Deliberately unlimited. It is read for a gap whose size has already been decided, over the same
  range - so it can answer no more rows than that gap holds, and a limit here would be a second
  bound on a thing already bounded.

  An op or entity type this node does not know stays the label it was written with, exactly as
  `read_unsent/2` leaves it.
  """
  @spec read_type_after(module, non_neg_integer, map) :: list(map)
  def read_type_after(entity_type, seq, data_match) do
    statement = """
    SELECT "seq", "op", "type", "entity_id", "data", #{@event_tail}
    FROM "#{Mapper.system_schema()}"."oplog"
    WHERE "type" = $1 AND "seq" > $2 AND "data" @> $3::jsonb
    ORDER BY "seq"
    """

    params = [Codec.encode_enum_value(entity_type), seq, data_match]

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, params)

    Enum.map(rows, &event/1)
  end

  @doc """
  Returns every committed effect with a seq above `sent_through` or in one of the given ranges of
  seqs, each a `{first, last}` pair, inclusive, in seq order. A reader sending effects as they
  commit names what it has sent so far: the highest seq it sent, and the seqs below it it hasn't
  sent, which are the serials of saves still running, or of ones that rolled back.

  The read is one statement, so a save's effects come back all together or not at all: a commit is
  atomic. A seq below an effect returned can belong to a save still running, which commits after,
  so a reader dating a place by what this returns dates it by the final limit (see
  `Hologram.Sync.FinalLimit`).

  The order is NOT commit order - a save takes its serials as it writes, and one that committed
  later can hold smaller ones. Nothing may materialize state by folding these in order: they say
  which entity types and attributes a save touched, and a reader wanting values reads the rows
  themselves.

  An op or entity type this node does not know stays the label it was written with, and data keys
  stay strings, as do the keys of the revisions and the old references, because a peer running a
  newer build can write names this node has never heard of - names that match nothing here, which
  is exactly what they should do.
  """
  @spec read_unsent(non_neg_integer, list({pos_integer, pos_integer})) :: list(map)
  def read_unsent(sent_through, unsent) do
    {firsts, lasts} = Enum.unzip(unsent)

    # The ranges go in as two arrays joined to the log, a range scan of its key each, so the read
    # costs a probe per range beside what it returns: they grow with the serials of saves running
    # while others commit, and with the rollbacks a limit held back hasn't passed yet.
    statement = """
    SELECT "seq", "op", "type", "entity_id", "data", #{@event_tail}
    FROM "#{Mapper.system_schema()}"."oplog"
    WHERE "seq" > $1
    UNION ALL
    SELECT "seq", "op", "type", "entity_id", "data", #{@event_tail}
    FROM "#{Mapper.system_schema()}"."oplog"
    JOIN unnest($2::bigint[], $3::bigint[]) AS "unsent" ("first", "last")
    ON "seq" BETWEEN "unsent"."first" AND "unsent"."last"
    ORDER BY "seq"
    """

    params = [sent_through, firsts, lasts]

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, params)

    Enum.map(rows, &event/1)
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

  # Every old reference is an entity id, or nil for a reference that was unset.
  defp old(%{old: old}) when is_map(old) do
    Map.new(old, fn {name, value} -> {name, Codec.encode_json(value, :uuid)} end)
  end

  defp old(_effect), do: nil

  # An op this build does not know stays the label it was written with, the same as an entity type
  # it has never compiled. A newer peer writing a seventh op is a thing a rolling deploy produces,
  # and raising here would take the dispatcher down mid-round - it restarts with no cursor and
  # resumes at the log's edge, so everything between would be skipped rather than retried.
  defp operation(label) do
    String.to_existing_atom(label)
  rescue
    ArgumentError -> label
  end

  defp event([
         seq,
         op,
         type,
         entity_id,
         data,
         tx,
         model_hash,
         actor_id,
         revisions,
         old,
         mutation_ref,
         inserted_at
       ]) do
    %{
      actor_id: Codec.decode(actor_id, :uuid),
      data: data,
      entity_id: Codec.decode(entity_id, :uuid),
      inserted_at: inserted_at,
      model_hash: model_hash,
      mutation_ref: mutation_ref,
      old: old,
      op: operation(op),
      revisions: revisions,
      seq: seq,
      tx: tx,
      type: entity_type(type)
    }
  end

  defp high_serial do
    statement = """
    SELECT "last_value", "is_called", #{run_sql()}
    FROM "#{Mapper.system_schema()}"."oplog_seq_seq"
    """

    {:ok, %Postgrex.Result{rows: [[serial, called?, run]]}} = Connection.query(statement)

    {if(called?, do: serial, else: 0), run}
  end

  # sobelow_skip ["SQL.Query"]
  defp insert(effects, model_hash, actor_id, mutation_ref) do
    values = Enum.flat_map(effects, &row(&1, model_hash, actor_id, mutation_ref))

    column_list = Enum.map_join(@columns, ", ", &Mapper.quote_identifier/1)
    row_list = row_placeholders(length(effects))

    statement =
      "INSERT INTO #{qualified_table()} (#{column_list}) VALUES #{row_list}"

    {:ok, _result} = Connection.query(statement, values)
  end

  defp notify do
    {:ok, _result} = Connection.query("SELECT pg_notify($1, '')", [@channel])

    :ok
  end

  defp qualified_table do
    "#{Mapper.quote_identifier(Mapper.system_schema())}.#{Mapper.quote_identifier("oplog")}"
  end

  defp row(
         %{op: op, entity_type: entity_type, entity_id: entity_id} = effect,
         model_hash,
         actor_id,
         mutation_ref
       ) do
    [
      Map.get(effect, :seq),
      Atom.to_string(op),
      Codec.encode_enum_value(entity_type),
      Codec.encode(entity_id, :uuid),
      data(effect),
      model_hash,
      actor_id,
      Map.get(effect, :revisions),
      old(effect),
      mutation_ref
    ]
  end

  defp row_placeholders(count) do
    column_count = length(@columns)

    Enum.map_join(0..(count - 1), ", ", fn index ->
      # The first column is the seq, which an effect without one takes from the sequence.
      [seq_slot | slots] = Enum.map(1..column_count, &"$#{index * column_count + &1}")

      "(COALESCE(#{seq_slot}::bigint, #{next_seq_sql()}), #{Enum.join(slots, ", ")})"
    end)
  end

  defp read_entry(condition, seq) do
    statement = """
    SELECT #{run_sql()}, "entry"."seq", "entry"."tx", "entry"."inserted_at"
    FROM (SELECT 1) AS "one"
    LEFT JOIN LATERAL (
      SELECT "seq", "tx", "inserted_at"
      FROM "#{Mapper.system_schema()}"."oplog"
      WHERE #{condition}
      ORDER BY "seq" DESC
      LIMIT 1
    ) AS "entry" ON true
    """

    case Connection.query(statement, [seq]) do
      {:ok, %Postgrex.Result{rows: [[run, nil, nil, nil]]}} ->
        {nil, run}

      {:ok, %Postgrex.Result{rows: [[run, entry_seq, tx, inserted_at]]}} ->
        {%{inserted_at: inserted_at, seq: entry_seq, tx: tx}, run}
    end
  end

  # The copy of the database names a restored dump, into this cluster or another, which carries the
  # marker and the run over and can land the log on the same file. The log's file names a reload
  # in place, a data-only one into the truncated tables leaving the copy as it was.
  defp log_id_expression(marker_id, run) do
    schema = Mapper.system_schema()

    ~s|md5(replace(#{marker_id}::text, '-', '') \|\| '/' \|\| #{run}::text \|\| '/' \|\| | <>
      ~s|(SELECT "id" FROM "#{schema}"."database_copy")::text \|\| '/' \|\| | <>
      ~s|pg_catalog.pg_relation_filenode('"#{schema}"."oplog"'::pg_catalog.regclass)::text)|
  end

  defp log_id_sql do
    schema = Mapper.system_schema()

    ~s|(SELECT #{log_id_expression(~s|"database"."log_id"|, ~s|"server_run"."run"|)} | <>
      ~s|FROM "#{schema}"."database" CROSS JOIN "#{schema}"."server_run")|
  end

  # The log id and the start time as a number, since its text form follows each session's
  # settings: a clean restart keeps the log id and starts a new run.
  defp run_sql do
    ~s|(#{log_id_sql()} \|\| '/' \|\| | <>
      ~s|(extract(epoch FROM pg_catalog.pg_postmaster_start_time()) * 1000000)::bigint::text)|
  end

  # An advisory key of 64 bits shows in pg_locks as its high and low halves, and is scoped to one
  # database.
  defp running_saves do
    <<class_id::32, object_id::32>> = <<@serial_lock_key::signed-64>>

    statement = """
    SELECT coalesce(array_agg("virtualtransaction"), '{}'), #{run_sql()}
    FROM pg_catalog.pg_locks
    WHERE "locktype" = 'advisory' AND "classid" = $1 AND "objid" = $2 AND "objsubid" = 1
      AND "mode" = 'ShareLock' AND "granted"
      AND "database" = (
        SELECT "oid" FROM pg_catalog.pg_database WHERE "datname" = current_database()
      )
    """

    {:ok, %Postgrex.Result{rows: [[saves, run]]}} =
      Connection.query(statement, [class_id, object_id])

    {MapSet.new(saves), run}
  end
end
