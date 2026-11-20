defmodule Hologram.Migrator do
  @moduledoc false

  require Logger

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Preflight
  alias Hologram.DB.Protocol
  alias Hologram.DB.Schema
  alias Hologram.DB.SchemaReconciler
  alias Hologram.DB.SortKey
  alias Hologram.Entity.Model
  alias Hologram.Migration.Loader
  alias Hologram.Migration.Renderer
  alias Hologram.Reflection

  # The ops the boot applies when the database holds an object under a name the current naming
  # rule no longer derives - see apply_renames/1.
  @rename_ops [:rename_constraint, :rename_enum_type, :rename_index, :rename_table]

  # Fixed application-defined key for the migration lock - serializes the whole boot
  # procedure of a deploy, whichever node gets there first. The value is frozen forever: a
  # different key breaks mutual exclusion across Hologram versions, so it must survive any
  # code move or rename. Provenance (for uniqueness, not for re-derivation): first 8 bytes
  # of md5("hologram_migrations") as a signed int64.
  #
  # EVERY statement that changes the schema runs under this key, on the one session that
  # holds it: the guard, each file's transaction, each tail's concurrent index build, the
  # index repair, and each step of Hologram.DB.IndexBuilder, which takes it per step on a
  # session of its own. A schema change this key does not cover is a deadlock on every deploy
  # where two nodes reach it together - a concurrent build waits for every transaction that
  # could see its table, and a schema change inside a transaction is exactly that.
  #
  # Taken ONLY with pg_try_advisory_lock, never pg_advisory_lock: a session queued on the
  # blocking form holds a snapshot and a virtual transaction for as long as it waits, and a
  # concurrent build waits for exactly those - so a queued waiter and the builder it waits
  # for deadlock. A loser polls instead, and each poll is a millisecond statement that opens
  # and closes between the build's waits, jamming nothing. Session-scoped rather than
  # transactional because a concurrent build cannot run inside a transaction at all, and
  # because it frees with its session, so a node that dies mid-procedure strands nobody.
  #
  # It covers the PROCEDURE rather than a file: a node holds off even its cheap
  # already-applied skips until it holds the key. At boot that costs nothing measurable -
  # the builds it would otherwise wait for are the same wait - and it is what keeps the rule
  # one sentence instead of a map of which phase runs under which key.
  #
  # Hologram.Migration.ShadowVerifier is the one caller outside this coverage, on purpose:
  # it applies to a throwaway database of its own, one verification at a time under a key of
  # its own, with no second session to exclude.
  #
  # A booting node that needs it also holds @boot_lock_key while it waits, which is what makes
  # Hologram.DB.IndexBuilder give way to it.
  @advisory_lock_key -335_777_576_117_788_795

  # Fixed application-defined key a booting node holds, shared, on the session it takes the
  # migration lock on - from before it starts polling for that lock until the session ends. Frozen
  # forever for the reason @advisory_lock_key is: a builder that reads another key never gives way.
  # Provenance: first 8 bytes of md5("hologram_migrations_boot") as a signed int64.
  #
  # Hologram.DB.IndexBuilder, once it holds the migration lock and before it runs a step, asks
  # whether any session holds this key (see boot_key_held?/0), and gives the lock back without a
  # step if one does. A builder that asked before a boot took the key held the migration lock when
  # the boot started waiting, so its step is the one the boot waits for; every builder taking the
  # lock after it sees the key. So a booting node waits for at most the step holding the lock when
  # it starts waiting, however many builders wait beside it. Its poll can still miss the lock now
  # and then, while a builder holds it just to ask, which costs a poll, never a step.
  #
  # Taken with pg_try_advisory_lock_shared, never queued, for the reason @advisory_lock_key is:
  # nobody takes it exclusively, so the try always wins, and booting nodes hold it side by side.
  # A session holding it between statements has no transaction and no snapshot, so a concurrent
  # build never waits for it. Freed with the session, like the migration lock the boot holds: a
  # node whose host vanishes without closing its connection keeps what it holds until the server
  # drops the session, and builders give way for that long - about a minute on a direct connection
  # once the session is between statements, given its keepalives (see
  # with_migration_connection/1), while a statement it was running runs to its end first.
  #
  # Every release holding the builder holds this key too - the builder never shipped without it.
  @boot_lock_key -8_943_570_201_190_700_407

  # How often a node that missed the migration lock looks again. A politeness knob, not a
  # correctness bound - the loop exits by winning the lock, never by a deadline.
  @migration_lock_poll_interval_ms 1_000

  # How many grants the re-derivation of their ids after a relabel reads at a time - it runs
  # in the file's transaction, and a rename of an entity type relabels every grant held on it.
  @grant_id_page_size 10_000

  @managed_by "migrations"

  # The cursor the first page of a grant id re-derivation reads after: no derived id and no
  # random one is the nil UUID, so every row sorts after it.
  @nil_uuid "00000000-0000-0000-0000-000000000000"

  @doc """
  Returns the versions of the migrations the connected database has applied.
  """
  @spec applied_versions() :: MapSet.t()
  def applied_versions do
    statement = ~s(SELECT "version" FROM "#{Mapper.system_schema()}"."migration")

    {:ok, %{rows: rows}} = Connection.query(statement)

    MapSet.new(rows, fn [version] -> version end)
  end

  @doc """
  Applies the given migrations to the connected database, one transaction each, and
  returns the model the last of them leaves behind.

  A file's statements and its bookkeeping row commit together, so the record can never
  disagree with the schema, and a failure leaves the earlier files applied - every
  inter-file state is a reviewed historical model state, which makes file boundaries the
  right transaction boundaries. The migration lock is the caller's to hold, and it serializes
  the appliers of a deploy: the first node does the work, the rest wait for the lock, then
  re-read the bookkeeping inside their own transaction and find each file already applied.
  Index builds that cannot run inside a transaction follow after the commit, under that same
  held lock.

  Every file is rendered before the first one applies, each from the model the one before it
  leaves: a change that meets an unbuilt unique index over rows repeating its key needs to
  know whether a later op takes that index away (see drop_removed_indexes/3). So a file the
  renderer refuses is refused with no file applied.

  The managed-object registry is deliberately left alone - it is schema reconciliation's
  record of what it created, and a migration-managed database has no use for it.
  """
  @spec apply_pending(list(%{atom => any}), %{atom => any}, %{atom => any}) :: %{atom => any}
  def apply_pending(migrations, pre_model, context) do
    {renders, post_model} =
      Enum.map_reduce(migrations, pre_model, fn migration, model ->
        render = Renderer.render(migration.ops, model)

        {render, render.post_model}
      end)

    migrations
    |> Enum.zip(renders)
    |> apply_migrations(context)

    post_model
  end

  @doc """
  Validates that folding the given migrations from the empty model produces the given
  model.

  Pure - it needs no database access, so it runs before anything is touched: a deploy
  whose model changes never became migrations refuses here, whether generation was
  skipped or CI was. A history still holding unanswered resolve! ops refuses first, naming
  each one's file and line - the build refuses drafts too, but an app can be built without
  the Hologram compiler.
  """
  @spec check_covered!(list(%{atom => any}), %{atom => any}) :: :ok
  def check_covered!(migrations, current_model) do
    unresolved = Loader.unresolved_entries(migrations)

    if unresolved != [] do
      raise "the migration draft is not resolved yet:\n" <>
              Loader.unresolved_lines(unresolved) <>
              "\nWrite the ops that express what happened, delete the resolve! lines, " <>
              "then finalize with mix holo.gen.migration."
    end

    replayed = Enum.reduce(migrations, Model.empty(), &Model.fold(&2, &1.ops))

    if replayed != current_model do
      differing = differing_changes(replayed, current_model)
      names = Enum.join(differing, ", ")

      raise "migration history does not produce this model - " <>
              "#{length(differing)} model #{changes_phrase(differing)} no migration " <>
              "(#{names}) - run mix holo.gen.migration"
    end

    :ok
  end

  @doc """
  Validates that the connected database's schema is exactly what the given model derives.

  Any difference refuses, one line per object - in a migration-managed database, removal
  ships as a migration whose drop already ran, so "ours but no longer in the model" never
  exists and every difference is drift: something added by hand, or something the model
  declares hand-dropped. One rule, no classifying - hologram_data is model-managed
  everywhere, and the wrong-database cases never reach this check (the marker refused
  them).

  The indexes the model leaves to the index plan are the one exception: a plain btree index
  named `...$idx` that isn't unique is the plan's (see `Hologram.DB.IndexPlan`), which
  `Hologram.DB.IndexBuilder` converges after the node starts serving, so this check neither asks
  for one nor refuses one. An index added by hand under any other name is still drift.
  """
  @spec check_drift!(%{module => %{atom => any}}) :: :ok
  def check_drift!(mapping) do
    drift_ops = drift_ops(mapping)

    if drift_ops != [] do
      lines = Enum.map_join(drift_ops, "\n", &"  * #{describe_difference(&1)}")

      raise "schema drift detected - the database does not match the model:\n" <>
              lines <>
              "\n#{Mapper.data_schema()} is model-managed - restore what is missing, remove what " <>
              "was added by hand, or express the change as a migration"
    end

    :ok
  end

  @doc """
  Returns a line describing the given schema-diff op as a difference between the
  database and the model - what the model declares that is missing, or what stands
  that the model does not derive.
  """
  @spec describe_difference(%{atom => any}) :: String.t()
  def describe_difference(%{op: :add_column} = op) do
    ~s(column "#{op.column}" on table "#{op.table}" declared by the model is missing)
  end

  def describe_difference(%{op: :add_enum_value} = op) do
    ~s(enum type "#{op.enum_type}" is missing the declared value '#{op.value}')
  end

  def describe_difference(%{op: :add_foreign_key} = op) do
    ~s(constraint "#{op.constraint}" on table "#{op.table}" declared by the model is missing)
  end

  def describe_difference(%{op: :alter_column} = op) do
    ~s(column "#{op.column}" on table "#{op.table}" does not match its declaration)
  end

  def describe_difference(%{op: :create_enum_type} = op) do
    ~s(enum type "#{op.enum_type}" declared by the model is missing)
  end

  def describe_difference(%{op: :create_index} = op) do
    ~s(index "#{op.index}" declared by the model is missing)
  end

  def describe_difference(%{op: :create_table} = op) do
    ~s(table "#{op.table}" declared by the model is missing)
  end

  def describe_difference(%{op: :drop_column} = op) do
    ~s(column "#{op.column}" on table "#{op.table}" is not derived from the model)
  end

  def describe_difference(%{op: :drop_enum_type} = op) do
    ~s(enum type "#{op.enum_type}" is not derived from the model)
  end

  def describe_difference(%{op: :drop_foreign_key} = op) do
    ~s(constraint "#{op.constraint}" on table "#{op.table}" is not derived from the model)
  end

  def describe_difference(%{op: :drop_index, non_plain: reasons} = op) do
    ~s(index "#{op.index}" is not derived from the model ) <>
      "(it has #{Enum.map_join(reasons, ", ", &describe_non_plain_reason/1)})"
  end

  def describe_difference(%{op: :drop_index} = op) do
    ~s(index "#{op.index}" is not derived from the model)
  end

  def describe_difference(%{op: :drop_table} = op) do
    ~s(table "#{op.table}" is not derived from the model)
  end

  def describe_difference(%{op: :rebuild_enum_type} = op) do
    ~s(enum type "#{op.enum_type}" does not hold the declared values in their order)
  end

  def describe_difference(%{op: :rename_constraint} = op) do
    ~s(constraint "#{op.from}" on table "#{op.table}" is named outside the derived scheme)
  end

  def describe_difference(%{op: :rename_enum_type} = op) do
    ~s(enum type "#{op.from}" is named outside the derived scheme - the model derives "#{op.to}")
  end

  def describe_difference(%{op: :rename_index} = op) do
    ~s(index "#{op.from}" on table "#{op.table}" is named outside the derived scheme - ) <>
      ~s(the model derives "#{op.to}")
  end

  def describe_difference(%{op: :rename_table} = op) do
    ~s(table "#{op.from}" is named outside the derived scheme - the model derives "#{op.to}")
  end

  @doc """
  Ensures the connected database is managed by migrations, claiming it when virgin -
  runs in the caller's transaction.

  A database containing neither Hologram schema is virgin: both schemas, the bookkeeping
  tables, and the marker are created, and :claimed is returned. A database whose marker
  matches the given context returns :managed. Every other state raises with a specific
  message: Hologram schemas without a marker, a marker belonging to another app or env,
  a database managed by schema reconciliation - dev's mechanism, which never shares a
  database with production - or system tables at a newer layout than the running one (see
  Hologram.DB.SchemaReconciler.system_schema_version/1, which reads the context's optional
  :system_upgrades). It never upgrades the system tables of a database it finds managed - that is
  Hologram.DB.SchemaReconciler.upgrade_system_tables!/1, which run/3 runs next in the same
  transaction.

  The migration lock is the caller's to hold - run/3 takes it before this runs and keeps it
  for the whole procedure. That exclusion is what makes a virgin database safe, since it is
  the one state every node of a deploy resolves the same way: without it they all read "no
  schemas" and all run CREATE SCHEMA, and the losers of that race fail their boot. The next
  node looks only once the claim has committed, and finds the marker.
  """
  @spec ensure_managed!(%{atom => any}) :: :claimed | :managed
  def ensure_managed!(context) do
    data_schema = Mapper.data_schema()
    system_schema = Mapper.system_schema()

    case hologram_schemas() do
      [] -> claim(context)
      [^data_schema, ^system_schema] -> check_marker!(context)
      _partial -> raise_not_managed!()
    end
  end

  @doc """
  Returns the given migrations the connected database has not applied yet, in their
  order.
  """
  @spec pending(list(%{atom => any}), MapSet.t()) :: list(%{atom => any})
  def pending(migrations, applied_versions) do
    Enum.reject(migrations, &(&1.version in applied_versions))
  end

  @doc """
  Records the given migration version as applied at the given time, under the hash of the
  model it produces, in the caller's transaction.

  The hash is of the model as it stands at that point in the history rather than of the
  current one, so each row pairs a position in the chain with the model shape reached there -
  which is what lets a row written under an older model be traced back to the migration that
  produced it.
  """
  @spec record_applied(String.t(), DateTime.t(), String.t()) :: :ok
  def record_applied(version, timestamp, model_hash) do
    statement = """
    INSERT INTO "#{Mapper.system_schema()}"."migration" ("version", "applied_at", "model_hash")
    VALUES ($1, $2, $3)
    """

    {:ok, _result} = Connection.query(statement, [version, timestamp, model_hash])

    :ok
  end

  @doc """
  Converges the indexes the given mapping derives - the primary keys' and the unique ones -
  rebuilding the ones PostgreSQL left invalid and creating the ones that are absent, and returns
  :ok. The index plan's indexes are `Hologram.DB.IndexBuilder`'s, which builds them once the node
  serves.

  Index builds are the one part of a migration that cannot ride its transaction, so they
  run after the file commits. A node dying in that window leaves the file recorded as
  applied and its index unfinished: invalid when the build had started, absent when it
  had not. Neither heals on its own - the file is no longer pending, so no later boot
  revisits it, and an invalid index still reads as present to the drift check.

  Indexes are the one object this repairs rather than reports. They carry no data, the
  model is their only author, and refusing instead would wedge every node of a fleet
  behind a state nothing can reach on its own. Everything else the drift check still
  refuses - an invalid index included, when the model does not derive it under that name
  and with that definition.

  The one state it refuses is rows repeating the key of a unique index it has to build.
  While the index is missing, nothing stops running nodes from writing them, and no build
  can succeed over them. The refusal names the table, the columns and how many keys
  repeat. Each index's rows are counted before it is built or dropped, so a refusal leaves
  that index as it was - the ones repaired before it stay repaired. A repeat written after
  the count fails the build instead, which leaves the index invalid under its name - the
  state the next boot counts and refuses the same way. Either way, the boot after the rows
  are fixed builds it.

  An invalid index is dropped and built again rather than rebuilt in place. REINDEX
  CONCURRENTLY builds a copy beside it, and a copy that fails - over repeated keys, or with
  the node killed partway - stays behind as one more invalid index the model does not
  derive. Dropped first, a node killed during the drop or the build leaves the index
  invalid under its own name, and killed in between leaves it absent, all of which the
  next boot repairs.

  Runs under the migration lock the caller holds, on that lock's own session: a concurrent
  build cannot run inside a transaction, and two nodes building the same index at the same
  moment deadlock each other. Holding the lock across it is also what tells in-progress work
  apart from abandoned work - a build registers its index invalid from the moment it starts,
  so a node able to see another's mid-flight build would read it as broken and rebuild it.

  A node that dies here strands nobody: the lock frees with its session, and the half-built
  index it leaves reads as invalid and is rebuilt by whoever takes the lock next.
  """
  @spec repair_indexes(%{module => %{atom => any}}) :: :ok
  def repair_indexes(mapping) do
    mapping
    |> invalid_derived_indexes()
    |> Enum.each(&rebuild_index!/1)

    mapping
    |> missing_indexes()
    |> Enum.each(&create_index!/1)

    :ok
  end

  @doc """
  Applies the pending migrations the project's migration modules define to the connected
  database as the current model's history.

  Idempotent, so it is safe to run ahead of boot as a release step (`bin/app eval
  "Hologram.Migrator.run()"`) - an apply that already ran leaves nothing pending, and
  the boot-time apply passes through. Same mechanism either way, nothing to configure.
  """
  @spec run() :: :ok
  def run do
    migrations = Loader.list!()
    current_model = Model.from_modules(Reflection.list_entities(), Reflection.list_roles())

    run(migrations, current_model, run_context())
  end

  @doc """
  Applies the given migrations' pending suffix to the connected database as the given
  model's history.

  The not-covered check runs first, before any database access - then the guard claims
  or verifies the database and brings its system tables to the running layout (one info
  line per step, see Hologram.DB.SchemaReconciler.upgrade_system_tables!/1), objects
  standing under names the current naming rule no longer derives are renamed (one info
  line each), and the pending files apply from the model the applied ones produce - with
  the indexes the applied files derive and the database lacks built before them, when the
  node knows every applied file. A unique one
  whose build fails on rows repeating its key is left invalid for the pending files, and
  the repair after them refuses it if they keep it - or the file that changes a type on its
  table, which rebuilds it, or fills a row repeating its key through it while it takes writes,
  refuses there. When a later op of the pending files removes the index, that file drops it
  ahead of its change instead and applies - unless the pending files also give the table a
  unique index, and a type change, fill or enum rebuild among them could change keys the
  dropped index would have been asked about (see removed_later?/4). The index repair and
  the drift check come last.

  The context carries the guard facts (:otp_app, :env) and the marker diagnostics
  (:hologram_version, :timestamp), and may carry :system_upgrades, steps in place of
  Hologram.DB.SchemaReconciler.system_schema_upgrades/0's (see system_schema_version/1), and
  :grant_id_page_size, how many grants a re-derivation of their ids reads at a time, both for
  tests only.
  """
  @spec run(list(%{atom => any}), %{atom => any}, %{atom => any}) :: :ok
  def run(migrations, current_model, context) do
    Connection.with_timeout(:infinity, fn ->
      run_migrations(migrations, current_model, context)
    end)
  end

  @doc """
  Runs the given function on a session of its own, opened against the database currently
  connected, and returns what it returns - the session the migration lock is taken on.

  Opened against the database currently connected rather than the configured one: they are the
  same at boot, and following the caller keeps the procedure honest wherever else the applier is
  pointed. A session of its own, because the migration lock is session-scoped and the pool would
  put the lock and the work on different connections. Stopping it releases the lock the boot
  procedure takes, which is why that procedure has no unlock statement - a node that dies
  mid-procedure frees it exactly the same way.

  The session ends for good when its connection is lost: no reconnect and no restart, so a
  statement after the loss fails or exits rather than run on a fresh connection - a new session
  holds no lock, and what the caller ran next would run unlocked. The caller is linked to the
  session, so one that runs on after such a loss traps exits. That includes a first connect that
  fails, which ends the caller's work at once rather than after a few tries: a boot fails loudly,
  for the release to start it again. And its statements run with no timeout of the server's,
  whatever the role or the database sets - an index build over a big table takes as long as it
  takes, and one cut short is left invalid, to be built again. Set by the session's first
  statement rather than as startup parameters, which a pooler may refuse, and only the ones the
  server knows: `transaction_timeout` is PostgreSQL 17's.

  It also runs with the pool's keepalives and user timeout (see
  Hologram.DB.Config.keepalive_statement/0): a node that vanishes holding the migration lock or the
  boot key holds up every other node's boot or index builds until the server drops its session.
  Best effort, as for the pool: a server refusing them is warned about and the session used as it
  is.
  """
  @spec with_migration_connection((-> any)) :: any
  def with_migration_connection(fun) do
    {:ok, %{rows: [[database]]}} = Connection.query("SELECT current_database()")

    connection_opts =
      Config.connection_opts(
        backoff_type: :stop,
        database: database,
        max_restarts: 0
      )

    # TODO(#1696): Postgrex.start_link/1 again, see Hologram.DB.Protocol.
    {:ok, connection_pid} = Protocol.start_link(connection_opts)

    try do
      Connection.with_connection(connection_pid, fn ->
        {:ok, _result} =
          Connection.query("""
          SELECT set_config(name, '0', false)
          FROM pg_catalog.pg_settings
          WHERE name IN ('lock_timeout', 'statement_timeout', 'transaction_timeout')
          """)

        apply_keepalives()

        fun.()
      end)
    after
      # A session already gone exits here, which would replace what the function raised.
      catch_exit_quietly(fn -> GenServer.stop(connection_pid) end)
    end
  end

  @doc """
  Returns whether a session on the current database holds the boot key - a booting node waiting
  for the migration lock, or running the procedure under it (see @boot_lock_key in this module).
  Work beside the boot procedure that takes the migration lock asks this once it holds the lock,
  and gives it back without doing anything when it's true.
  """
  @spec boot_key_held?() :: boolean
  def boot_key_held? do
    # pg_locks lists every database's locks, and shows a bigint key's high half in classid, its low
    # half in objid and 1 in objsubid.
    statement = """
    SELECT EXISTS (
      SELECT 1 FROM pg_catalog.pg_locks
      WHERE "locktype" = 'advisory' AND "objsubid" = 1
        AND "database" = (
          SELECT "oid" FROM pg_catalog.pg_database WHERE "datname" = current_database()
        )
        AND (("classid"::bigint << 32) | "objid"::bigint) = $1
    )
    """

    {:ok, %{rows: [[held?]]}} = Connection.query(statement, [@boot_lock_key])

    held?
  end

  @doc """
  Runs the given function under the migration lock, taken on the current session by polling (see
  @advisory_lock_key in this module) and released once the function returns or raises, and
  returns what the function returns. For work beside the boot procedure that changes the schema,
  one step at a time - each step holds the lock no longer than it takes. The given function has to
  ask boot_key_held?/0 first, and return without doing anything when it's true, so a booting node
  waits for no step that starts after it started waiting. Polls at the given interval, the boot's
  when absent.
  """
  @spec with_migration_lock((-> any), pos_integer) :: any
  def with_migration_lock(fun, poll_interval_ms \\ @migration_lock_poll_interval_ms) do
    acquire_migration_lock(poll_interval_ms)

    try do
      fun.()
    after
      # Whatever it answers or however it ends: on a session that died, the lock went with it, and
      # matching or exiting here would replace what the function raised.
      catch_exit_quietly(fn ->
        Connection.query("SELECT pg_advisory_unlock($1)", [@advisory_lock_key])
      end)
    end
  end

  # The re-read inside the transaction stays, and is not redundant with the lock: the lock
  # keeps two nodes from applying at once, and this is what tells a node that WAITED for it
  # that the file it was about to apply is already there.
  defp apply_migration(migration, render, later_ops, context) do
    {:ok, status} =
      Connection.transaction(fn ->
        if migration.version in applied_versions() do
          :skipped
        else
          apply_transactional(render, later_ops, migration.version, context)
        end
      end)

    if status == :applied and render.tail != [] do
      execute_tail_ops(render.tail)
    end

    :ok
  end

  # Each file takes the ops of the files after it, tails included, for the look-ahead of
  # drop_removed_indexes/3.
  defp apply_migrations([], _context), do: :ok

  defp apply_migrations([{migration, render} | rest], context) do
    later_ops =
      Enum.flat_map(rest, fn {_migration, later} -> later.transactional ++ later.tail end)

    apply_migration(migration, render, later_ops, context)
    apply_migrations(rest, context)
  end

  # Acquired by polling, never by queuing - see @advisory_lock_key. The work behind the lock
  # is ours to do, so there is no done-by-someone-else exit: the loop ends by winning it.
  defp acquire_migration_lock(poll_interval_ms \\ @migration_lock_poll_interval_ms) do
    unless try_migration_lock?() do
      Process.sleep(poll_interval_ms)
      acquire_migration_lock(poll_interval_ms)
    end
  end

  # A required column with no explicit backfill carries its declared default as one - the
  # renderer stamps it, which is what schema reconciliation does for the same declaration in
  # dev: the two mechanisms have to leave the same rows behind, not merely the same columns.
  # The default is the one the add's chunk leaves, which reconciliation's one diff also uses
  # when the declaration arrives in one go.
  #
  # The fill writes every row, so an invalid unique index that still checks writes, over
  # rows repeating its key, is asked about first - see drop_removed_indexes/3.
  defp apply_op(%{op: :add_column, backfill: value} = op, later_ops) do
    drop_removed_indexes(op.table, :update, later_ops)
    add_column_filled(op, value)
  end

  # The NULLs take the declared default before the column tightens over them. Only when
  # there are any: an enum value added in this transaction cannot be used in it, not even as
  # the parameter of an UPDATE that matches no row. Asked before the fill: under a unique
  # index that stands, a fill making rows repeat a key would fail in PostgreSQL - and so would
  # one writing a row that already repeats the key of an invalid one that still checks writes.
  defp apply_op(%{op: :alter_column, fill: value} = op, later_ops) do
    if count_result(DDL.null_check_statement(op.table, op.column)) > 0 do
      drop_removed_indexes(op.table, {:fill, op.column}, later_ops)
      Preflight.check_fill!(op)
      fill_with_companions(op, value)
    end

    execute_statements(DDL.statements(op))
  end

  # A type change asks about the unique indexes standing over its column right before it
  # applies: two values can convert to one, and the names a file's earlier ops leave behind
  # are the ones the database holds at this point. A tightening carrying a fill keeps its
  # type, so the clause above has no cast to ask about. It drops the plan's indexes over a column
  # cast to text then too.
  #
  # The change rebuilds every index on the table, so an invalid unique one over rows that
  # already repeat its key is asked about first - the cast's own check would blame the cast
  # for the repeats. One a later op removes is dropped here instead, which also keeps it out
  # of the cast's check.
  defp apply_op(%{op: :alter_column} = op, later_ops) do
    if op.before.type != op.after.type do
      drop_removed_indexes(op.table, {:rewrite, [op.column]}, later_ops)
    end

    Preflight.check_cast!(op)
    drop_plan_indexes_cast_to_text(op)

    execute_statements(DDL.statements(op))
  end

  # Converting each column to the rebuilt type rewrites its table, which rebuilds every index
  # on it - see the alter_column clause above.
  defp apply_op(%{op: :rebuild_enum_type} = op, later_ops) do
    op.columns
    |> Enum.group_by(fn {table, _column} -> table end, fn {_table, column} -> column end)
    |> Enum.sort()
    |> Enum.each(fn {table, columns} ->
      drop_removed_indexes(table, {:rewrite, columns}, later_ops)
    end)

    execute_statements(DDL.statements(op))
  end

  # A rename or a drop of an index skips one that is not there: an earlier op of this boot's
  # pending files may have dropped it ahead of its change - see drop_removed_indexes/3. On a
  # history this node fully knows nothing else leaves it missing, since the indexes the
  # applied files derive were created before the pending files (create_applied_indexes/4).
  #
  # Every caller of apply_pending/3 gets the skip, on purpose - the applier on a history it
  # does not fully know and the shadow verifier's replay included, neither of which drops an
  # index early. A missing index is the one state the boot repairs rather than reports, and a
  # skipped op cannot hide a wrong result: the repair builds what the model derives and is
  # missing, and the drift check and the shadow verifier compare the schema the files leave
  # with the model's.
  defp apply_op(%{op: kind} = op, _later_ops) when kind in [:drop_index, :rename_index] do
    op
    |> Map.put(:if_exists, true)
    |> DDL.statements()
    |> execute_statements()
  end

  # A grant's id is derived from its labels, so the grants a rename relabeled take the ids their
  # new labels derive - the id the browser and the server's batches look a grant up by. Grants
  # repeating one another's four identity columns would derive one id, so they are refused
  # first, by name.
  defp apply_op(%{op: :rederive_grant_ids} = op, _later_ops) do
    Preflight.check_grant_repeats!(op)
    rederive_grant_ids(op, @nil_uuid)
  end

  defp apply_op(op, _later_ops), do: execute_statements(DDL.statements(op))

  # Each op is checked right before it applies, against the database the ops before it
  # left: a check read once for the whole file would look for a renamed attribute or entity
  # under its new name in a database that still has the old one. A refusal takes back the
  # ops before it with the transaction.
  defp apply_ops([], _later_ops), do: :ok

  defp apply_ops([op | rest], later_ops) do
    Preflight.check!(op)
    apply_op(op, rest ++ later_ops)
    apply_ops(rest, later_ops)
  end

  # Added nullable, filled, then tightened - the value never travels in the DDL, and the
  # rows that predate the column receive it.
  defp add_column_filled(op, encoded_value) do
    nullable_definition = %{op.definition | null: true}

    execute_statements(DDL.statements(%{op | definition: nullable_definition}))
    fill_column(op.table, op.column, encoded_value)

    if not op.definition.null do
      tighten_op = %{
        op: :alter_column,
        table: op.table,
        column: op.column,
        before: nullable_definition,
        after: op.definition
      }

      execute_statements(DDL.statements(tighten_op))
    end
  end

  # The ops after each one - the rest of the file, its tail, then the later files - are what
  # drop_removed_indexes/3 looks ahead through.
  defp apply_transactional(render, later_ops, version, context) do
    page_size = Map.get(context, :grant_id_page_size, @grant_id_page_size)

    render.transactional
    |> Enum.map(&put_grant_id_page_size(&1, page_size))
    |> apply_ops(render.tail ++ later_ops)

    mapping = Mapper.derive_from_model!(render.post_model)

    # A companion this file adds is filled AFTER every op has applied, not at its own add:
    # the diff applies add_column before alter_column, so a source column being cast to
    # text in the same file still holds its old type when its companion lands. The renderer
    # names the added columns as the file leaves them, so a rename after the add is followed.
    # It writes only the rows whose source holds a value. A companion comes with a text
    # attribute, so its source either arrives with this file, holding values only when an add
    # filled them, or turns text with a type change - both of which asked about the invalid
    # unique indexes on the table already, against these same rows (see apply_op/2).
    SchemaReconciler.backfill_companions!(render.added_columns, mapping)

    # The tail's checks run here, against the schema the statements above just produced and
    # before anything commits: a file whose index cannot be built does not apply at all,
    # rather than committing and failing afterwards. They read the schema after every op,
    # companions filled, so a column this file adds and fills is counted like any other - a
    # check against an absent column answers zero, which a backfilled unique column must not
    # get.
    Preflight.run!(render.tail, Introspection.schema(), mapping)

    record_applied(version, context.timestamp, Model.hash(render.post_model))

    :applied
  end

  # A database holding an object under a name the current naming rule no longer derives - one
  # a release that changed the rule left behind - can't be fixed by a migration: replay derives
  # both sides with the current rule, so there is no difference for a file to express. The
  # boot renames it instead, in one transaction and ahead of the pending migrations, whose
  # ops name objects by the current rule and would otherwise fail on the old name. The
  # diff is against what the applied migrations derive, and only its renames apply: anything
  # else it finds is the pending files' to change, the index repair's to rebuild, or the drift
  # check's to refuse.
  #
  # Only a node whose chain holds every applied version heals (see known_history?/2). One that
  # lacks some is most often an older release booting after a newer one migrated the database,
  # which the drift check refuses, so renaming the newer release's objects back would gain
  # nothing. The plan's indexes are Hologram.DB.IndexBuilder's to rename, once the node serves. An
  # older release that differs only by its naming rule does rename back, which is what it needs to
  # boot once the newer nodes are stopped. Old and new nodes running against one database at once
  # is a separate matter, not supported yet (#1627).
  defp apply_renames(pre_model) do
    expected =
      pre_model
      |> Mapper.derive_from_model!()
      |> Schema.from_mapping()

    renames =
      Introspection.schema()
      |> Schema.diff(expected)
      |> Enum.filter(&(&1.op in @rename_ops))

    if renames != [] do
      {:ok, _result} =
        Connection.transaction(fn ->
          Enum.each(renames, &execute_statements(DDL.statements(&1)))
        end)

      Enum.each(renames, &log_rename/1)
    end

    :ok
  end

  # A unique_violation is rows repeating the key. A key a running node repeats while the build
  # runs is the same refusal: a count before the build sees only the rows written by then.
  defp build_index(op) do
    [statement] = DDL.statements(op)

    case Connection.query(statement) do
      {:ok, _result} ->
        :ok

      {:error, %Postgrex.Error{postgres: %{code: :unique_violation}} = error} ->
        {:repeated_keys, error}

      {:error, error} ->
        raise error
    end
  end

  # Counted again for the refusal, which names how many keys repeat. Rows fixed between the
  # failed build and the count leave nothing to name, so the build's own error stands.
  defp build_index!(op) do
    with {:repeated_keys, error} <- build_index(op) do
      Preflight.check_unique_index!(op)
      raise error
    end
  end

  defp catch_exit_quietly(fun) do
    fun.()
  catch
    :exit, _reason -> :ok
  end

  defp changes_phrase([_one]), do: "change has"

  defp changes_phrase(_differing), do: "changes have"

  defp check_marker!(context) do
    marker = SchemaReconciler.read_marker()

    cond do
      marker == nil ->
        raise_not_managed!()

      marker.otp_app != context.otp_app ->
        raise "the configured database belongs to app \"#{marker.otp_app}\" - " <>
                "the current app is \"#{context.otp_app}\" - " <>
                "point the config at the right database"

      marker.env != context.env ->
        raise "the configured database belongs to the \"#{marker.env}\" env - " <>
                "the current env is \"#{context.env}\" - " <>
                "the config points at another env's database"

      marker.managed_by == "reconciliation" ->
        raise "the configured database is managed by schema reconciliation, which " <>
                "converges dev databases from the model - migrations never apply to " <>
                "one - point the config at a database of this environment"

      marker.managed_by != @managed_by ->
        raise "the configured database is managed by #{marker.managed_by} - " <>
                "the migration applier never touches it"

      true ->
        SchemaReconciler.check_system_schema_version!(marker, context)
        :managed
    end
  end

  defp check_unique_keys!(%{unique: true} = op), do: Preflight.check_unique_index!(op)

  defp check_unique_keys!(_op), do: :ok

  # The one path that builds the system tables, at the running layout. A database already claimed
  # goes through check_marker!/1 above, which refuses a newer layout, and the upgrade steps carry
  # an older one forward (see Hologram.DB.SchemaReconciler.system_schema_upgrades/0).
  defp claim(context) do
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "#{Mapper.system_schema()}"))
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "#{Mapper.data_schema()}"))

    SchemaReconciler.create_system_tables()

    SchemaReconciler.write_marker(%{
      otp_app: context.otp_app,
      env: context.env,
      managed_by: @managed_by,
      hologram_version: context.hologram_version,
      system_schema_version: SchemaReconciler.system_schema_version(context),
      last_reconciled_at: context.timestamp
    })

    :claimed
  end

  defp companion_key(:search_key, value), do: SortKey.search_key(value)

  defp companion_key(:sort_key, value), do: SortKey.compute(value)

  defp count_result(statement) do
    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count
  end

  # A file builds some of its indexes after it commits, so a node that stopped in between
  # leaves the file recorded as applied and its index absent. A pending type change or fill
  # asks the unique indexes standing over its column whether it makes keys repeat, and an
  # absent one is not asked: the change would go through, and the repair after the files
  # would refuse over keys the change itself made repeat - two values a cast turned into one
  # included, which nothing tells apart again. So the indexes the applied files derive are
  # created first, and the pending changes meet every index they have to ask. A pending
  # rename or drop of one does not need it there, since it skips an index that is missing (see
  # apply_op/2), so for a pending drop this is a build the file takes back at once - the
  # price of a crash in that window being followed by a release that drops that very index.
  #
  # Creating only, never rebuilding: an invalid index holds its name, so the pending files
  # meet it as it is, and the repair after the files rebuilds whatever survives them.
  # Rebuilding it here would refuse rows repeating its key on every boot, even for a release
  # whose pending file drops that index.
  #
  # For the same reason a build that fails on such rows is not refused here. It leaves the
  # index invalid under its name, where the pending changes find it. A pending file that
  # drops the index, or the table it stands on, takes it away, and the boot gets through.
  # One that keeps it leaves it to the repair after the files, which refuses it there, with
  # the pending files applied. A pending type change on its table rebuilds every index there,
  # this one included, and a pending fill that writes a repeated row through one that takes
  # writes fails on it, so either refuses at its file instead - unless the ops after it take
  # the index away, which is then dropped ahead of the change (see drop_removed_indexes/3).
  # No count first: the failed build is what leaves the index for those changes to meet, so
  # it runs either way.
  #
  # With nothing pending the applied files derive the current model, so the repair after
  # them does the same work. On a history this node does not fully know, what the applied
  # files derive is not what the database holds - see apply_renames/1.
  defp create_applied_indexes(migrations, applied, pending, pre_model) do
    if pending != [] and known_history?(migrations, applied) do
      pre_model
      |> Mapper.derive_from_model!()
      |> missing_indexes()
      |> Enum.each(&build_index(Map.put(&1, :concurrently, true)))
    end

    :ok
  end

  # Counted before the build, so a refusal leaves nothing behind - a failed build would leave
  # the index invalid under its name.
  defp create_index!(op) do
    check_unique_keys!(op)
    build_index!(Map.put(op, :concurrently, true))
  end

  defp describe_non_plain_reason(:collation), do: "a collation other than its column's"

  defp describe_non_plain_reason(:constraint), do: "an owning constraint"

  defp describe_non_plain_reason(:expression), do: "an expression"

  defp describe_non_plain_reason(:include), do: "INCLUDE columns"

  defp describe_non_plain_reason(:method), do: "an access method other than btree"

  defp describe_non_plain_reason(:operator_class), do: "a non-default operator class"

  defp describe_non_plain_reason(:predicate), do: "a predicate"

  defp describe_non_plain_reason(:sort_order), do: "a non-default sort order"

  # Everything the term carries, so the count can never come out empty while the terms
  # differ. The designation names no module of its own - it is a fact about one - so it
  # reads as itself rather than as the type it points at, which is covered on its own.
  defp differing_changes(replayed, current) do
    entity_names =
      replayed.entities
      |> Map.keys()
      |> Enum.concat(Map.keys(current.entities))
      |> Enum.uniq()
      |> Enum.filter(&(replayed.entities[&1] != current.entities[&1]))

    role_names =
      replayed.roles
      |> Map.keys()
      |> Enum.concat(Map.keys(current.roles))
      |> Enum.uniq()
      |> Enum.filter(&(replayed.roles[&1] != current.roles[&1]))

    designation =
      if replayed.user_entity == current.user_entity,
        do: [],
        else: ["the user entity designation"]

    entity_names
    |> Enum.concat(role_names)
    |> Enum.map(&inspect/1)
    |> Enum.sort()
    |> Enum.concat(designation)
  end

  # A column cast to text keeps its indexes - PostgreSQL rebuilds them over the raw text, which no
  # plan index holds: a btree entry is capped near 2.7 kB, so a longer value would fail its write
  # until the builder dropped the index. Dropped here instead, in the file's transaction, whose
  # cast locks the table anyway, and the builder builds the plan's index over the sort key once the
  # node serves.
  defp drop_plan_indexes_cast_to_text(
         %{before: %{type: before_type}, after: %{type: "text"}} = op
       )
       when before_type != "text" do
    actual = Introspection.schema()
    owned_names = IndexPlan.owned_index_names(actual)

    for {name, index} <- Enum.sort(actual.tables[op.table].indexes),
        MapSet.member?(owned_names, name),
        op.column in index.columns do
      execute_statements(DDL.statements(%{op: :drop_index, index: name}))
    end

    :ok
  end

  defp drop_plan_indexes_cast_to_text(_op), do: :ok

  # What differs between the database and what the given mapping derives, leaving out the index
  # plan's indexes (see check_drift!/1).
  defp drift_ops(mapping) do
    actual = Introspection.schema()
    plan_names = IndexPlan.owned_index_names(actual)

    actual
    |> Schema.diff(Schema.from_mapping(mapping))
    |> Enum.reject(&(&1.op == :drop_index and MapSet.member?(plan_names, &1.index)))
  end

  # A concurrent build that failed partway leaves the index in the catalog flagged
  # invalid: it holds the name and serves no query. A file's tail runs only when the file
  # applies, so the one it meets stood under the name before - the index of a deploy that
  # crashed after its commit is the repair's to rebuild, since the file is no longer pending.
  # Dropped concurrently, as it was built - see rebuild_index!/1.
  defp drop_invalid_index(index) do
    if count_result(DDL.invalid_index_check_statement(index)) > 0 do
      execute_statements(DDL.statements(%{op: :drop_index, index: index, concurrently: true}))
    end
  end

  # A type change rebuilds every index on its table, and a fill writes through every index
  # that takes writes, so either fails on an invalid unique index over rows repeating its key -
  # the one the build before the pending files leaves over such rows (create_applied_indexes/4),
  # or a tail's build that a running node's write failed. When the index stays, the change is
  # refused, naming the rows (Preflight.check_invalid_unique_indexes!/3). When an op after
  # this one takes the index away (removed_later?/4), the rows are about to stop mattering,
  # so the index is dropped here and the change goes on.
  #
  # Dropped inside the file's transaction: a refusal later in the file takes the drop back,
  # and a node stopping after the commit leaves the index absent under an applied file, which
  # the next boot builds again before its pending files - invalid over the same rows, taking
  # no writes - and meets the same way. A plain drop, which locks the table against reads
  # until the commit. A type change, an enum rebuild and an add take that lock themselves; a
  # fill takes it only at its tightening, so here it comes ahead of the fill's UPDATE.
  #
  # Logged as it runs, like any step of a file, so a refusal later in the file follows a line
  # about a drop the transaction took back.
  #
  # The op that removes the index names one that is gone by then - see the apply_op/2 clause
  # for :drop_index and :rename_index.
  defp drop_removed_indexes(table, change, later_ops) do
    removable? = fn index, covered? -> removed_later?(index, table, covered?, later_ops) end

    table
    |> Preflight.check_invalid_unique_indexes!(change, removable?)
    |> Enum.each(fn index ->
      execute_statements(DDL.statements(%{op: :drop_index, index: index}))

      Logger.info(
        ~s(Hologram: dropping unbuilt unique index "#{index}" on table "#{table}" ahead of a ) <>
          "change it would fail - a later migration op removes it"
      )
    end)
  end

  defp execute_statements(statements) do
    Enum.each(statements, fn statement ->
      {:ok, _result} = Connection.query(statement)
    end)
  end

  # Asked for rather than done: the applier records a migration inside its transaction and builds
  # the tail's indexes after it commits, so in between another node finds the chain applied,
  # reaches its own repair, and can build the very index this tail is about to. Both nodes are
  # asking for the same index, and the second one to get the lock finds it already there.
  #
  # An INVALID one is not that - it is a build that died partway, which the line above drops so
  # this one rebuilds it.
  #
  # The file's check found no repeated key before it committed, but nothing enforces the key
  # until this build finishes, so a running node can write one in between. The build then
  # refuses as the check would have, and leaves the index invalid for the next boot's repair,
  # which refuses the same way until the rows are fixed.
  #
  # CONCURRENTLY is not decided here: the renderer decides what belongs in the tail at all, and
  # what it decides IS concurrent - it stamps every op it puts there, because being unable to run
  # inside the migration's transaction is the whole reason the tail exists.
  defp execute_tail_op(%{op: :create_index} = op) do
    drop_invalid_index(op.index)

    if count_result(DDL.built_index_check_statement(op.index)) == 0 do
      build_index!(op)
    end
  end

  # Runs on the migration lock's session, which by now holds no open transaction - the file
  # committed above - which is what a concurrent build needs. The lock is already held and has
  # to be: unlocked, a node applying the NEXT file deadlocks against this build outright, and a
  # node reaching its own repair reads this half-built index as broken and rebuilds it, which
  # is two concurrent builds on one relation waiting on each other's virtual transactions.
  defp execute_tail_ops(tail) do
    Enum.each(tail, &execute_tail_op/1)
  end

  defp fill_column(table, column, encoded_value) do
    fill_statement = DDL.fill_statement(table, column)

    {:ok, _result} = Connection.query(fill_statement, [encoded_value])
  end

  # A node whose chain lacks an applied version runs older code than the database, or the version
  # was removed from the chain. Most such gaps change the schema, and the drift check refuses them
  # before anything is built - an index on a column the database lacks included. One that left the
  # schema alone, like a role's change, passes it, and the node repairs the model's indexes as any
  # boot does.
  defp converge_for_unknown_chain(mapping) do
    check_drift!(mapping)
    repair_indexes(mapping)
  end

  # Every filled row takes the one value, so its companions take one key each, set in the
  # same statement - on the rows the fill reaches only, where the companion fill after the
  # ops would recompute every row of the table.
  # sobelow_skip ["SQL.Query"]
  defp fill_with_companions(op, encoded_value) do
    assignments = [
      {op.column, encoded_value}
      | Enum.map(op.fill_companions, fn {kind, name} ->
          {name, companion_key(kind, encoded_value)}
        end)
    ]

    set_sql =
      assignments
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {{name, _value}, position} ->
        "#{Mapper.quote_identifier(name)} = $#{position}"
      end)

    table = ~s("#{Mapper.data_schema()}".#{Mapper.quote_identifier(op.table)})
    column = Mapper.quote_identifier(op.column)
    statement = "UPDATE #{table} SET #{set_sql} WHERE #{column} IS NULL"

    {:ok, _result} = Connection.query(statement, Enum.map(assignments, &elem(&1, 1)))
  end

  defp follow_index(
         %{op: :alter_column, table: table} = op,
         %{removed?: false, table: table} = walked
       ) do
    writes? = Map.has_key?(op, :fill) or op.before.type != op.after.type

    {:cont, %{walked | written?: walked.written? or writes?}}
  end

  defp follow_index(%{op: :create_index, table: table, unique: true}, %{table: table} = walked) do
    {:cont, %{walked | unique?: true}}
  end

  defp follow_index(%{op: :drop_index, index: index}, %{index: index, removed?: false} = walked) do
    {:cont, %{walked | removed?: true}}
  end

  # The table's rows go with it, so a table a later op creates under the name starts empty,
  # and nothing after this matters.
  defp follow_index(%{op: :drop_table, table: table}, %{table: table} = walked) do
    {:halt, %{walked | removed?: true}}
  end

  defp follow_index(%{op: :rebuild_enum_type} = op, %{removed?: false} = walked) do
    writes? = Enum.any?(op.columns, fn {table, _column} -> table == walked.table end)

    {:cont, %{walked | written?: walked.written? or writes?}}
  end

  defp follow_index(
         %{op: :rename_index, from: index} = op,
         %{index: index, removed?: false} = walked
       ) do
    {:cont, %{walked | index: op.to}}
  end

  defp follow_index(%{op: :rename_table, from: table} = op, %{table: table} = walked) do
    {:cont, %{walked | table: op.to}}
  end

  defp follow_index(_op, walked), do: {:cont, walked}

  defp hologram_schemas do
    statement = """
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname IN ('#{Mapper.data_schema()}', '#{Mapper.system_schema()}')
    ORDER BY nspname
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [name] -> name end)
  end

  # Only the invalid indexes the model derives under that name, with the definition the
  # model gives it: the repair builds the model's definition, so rebuilding one that differs
  # would replace an object nobody derived. Those are drift for the check to report. So is
  # an invalid index under a name the model doesn't derive, like the copy a REINDEX
  # CONCURRENTLY run by hand leaves when it fails.
  defp invalid_derived_indexes(mapping) do
    case invalid_indexes() do
      [] -> []
      invalid -> invalid_derived_indexes(invalid, Introspection.schema(), mapping)
    end
  end

  defp invalid_derived_indexes(invalid, actual, mapping) do
    derived =
      for {table, table_definition} <- Schema.from_mapping(mapping).tables,
          {index, definition} <- table_definition.indexes,
          into: %{} do
        {index, {table, definition}}
      end

    for index <- invalid,
        {table, definition} <- List.wrap(derived[index]),
        get_in(actual.tables, [table, :indexes, index]) == definition do
      Map.merge(%{op: :create_index, table: table, index: index}, definition)
    end
  end

  defp invalid_indexes do
    statement = DDL.invalid_indexes_statement(true)
    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [index, _ready?, _live?] -> index end)
  end

  defp known_history?(migrations, applied) do
    known_versions = MapSet.new(migrations, & &1.version)

    Enum.all?(applied, &MapSet.member?(known_versions, &1))
  end

  defp log_rename(op) do
    kind =
      case op.op do
        :rename_constraint -> "constraint"
        :rename_enum_type -> "enum type"
        :rename_index -> "index"
        :rename_table -> "table"
      end

    Logger.info(
      ~s(Hologram: renamed #{kind} "#{op.from}" to "#{op.to}" to follow the current naming rule)
    )
  end

  defp put_grant_id_page_size(%{op: :rederive_grant_ids} = op, page_size) do
    Map.put(op, :page_size, page_size)
  end

  defp put_grant_id_page_size(op, _page_size), do: op

  defp raise_not_managed! do
    raise "the configured database contains Hologram schemas but no managed-database " <>
            "marker - it is not managed by migrations - drop the " <>
            ~s("#{Mapper.system_schema()}" and "#{Mapper.data_schema()}" schemas or point the config ) <>
            "at another database"
  end

  # Read again inside the lock: the node that held it before may have finished everything
  # already, which is the common case for every node of a deploy but the first. Read before it too,
  # to tell whether the boot needs the lock at all (see up_to_date?/3).
  # Only what the model derives: an index the mapping does not name is drift for the
  # check to report, never something to create. A table the database does not have is
  # drift as well, and is skipped - creating its indexes would raise a relation error here,
  # before check_drift!/1 gets to name the missing table as the cause - and so is a column it
  # does not have, for the same reason. So is a name an index
  # already holds, whatever its definition, and an index the diff recognises as renamed:
  # building the derived one beside it would leave two, and the drift check names both.
  defp missing_indexes(mapping) do
    actual = Introspection.schema()

    held_names =
      actual.tables
      |> Enum.flat_map(fn {_table, definition} -> Map.keys(definition.indexes) end)
      |> MapSet.new()

    actual
    |> Schema.diff(Schema.from_mapping(mapping))
    |> Enum.filter(fn op ->
      op.op == :create_index and Map.has_key?(actual.tables, op.table) and
        Enum.all?(op.columns, &Map.has_key?(actual.tables[op.table].columns, &1)) and
        not MapSet.member?(held_names, op.index)
    end)
  end

  # Counted before the drop, so a refusal leaves the index as it was: a build that failed on
  # repeated keys enforces nothing, but one killed while validating its rows already refuses
  # new writes that repeat the key, and dropping it would let them through. Dropped
  # concurrently, as it was built: a plain drop locks every query on the table out until the
  # longest transaction reading it ends.
  defp rebuild_index!(op) do
    check_unique_keys!(op)
    execute_statements(DDL.statements(%{op: :drop_index, index: op.index, concurrently: true}))
    build_index!(Map.put(op, :concurrently, true))
  end

  # Paged by id, from just past the last id read. A row not read yet keeps its old id, so it
  # stays ahead of the cursor until its page comes; a row given a new id lands either behind
  # the cursor, never read again, or ahead of it, where it is read again and derives the id it
  # now has. So each row moves once, and the pages end. Within one page a new id never meets
  # another row's: a row holding it would hold the same four columns, which the store's unique
  # index refuses (see Hologram.Auth.RoleGrant.identity_columns/0) - and, where that index was
  # missing or unbuilt, the count before the first page (see the apply_op/2 clause).
  defp rederive_grant_ids(op, after_id) do
    statement = DDL.grant_identity_statement(op.table, op.column)

    {:ok, %{rows: rows}} = Connection.query(statement, [op.value, after_id, op.page_size])

    moved =
      for [id, user_id, entity_type, entity_id, role] <- rows,
          derived = RoleGrant.derive_id_from_labels(user_id, entity_type, entity_id, role),
          derived != id,
          do: {id, derived}

    if moved != [] do
      {old_ids, new_ids} = Enum.unzip(moved)

      update_statement = DDL.grant_id_update_statement(op.table)

      {:ok, _result} = Connection.query(update_statement, [old_ids, new_ids])
    end

    if length(rows) == op.page_size do
      [last_id | _identity] = List.last(rows)

      rederive_grant_ids(op, last_id)
    else
      :ok
    end
  end

  # Whether the ops after a change take the given index away, so the change may go on
  # without it - see drop_removed_indexes/3. The walk follows the index through the renames of
  # itself and of its table to the op that drops it, or drops its table.
  #
  # Dropping the index early also takes away what it would have told the changes before its
  # removal: a type change or a fill asks only the unique indexes standing over its column
  # whether it makes keys repeat (Preflight.check_cast!/1, check_fill!/1), and two values a
  # cast turns into one cannot be told apart again. That loss is harmless while no unique
  # index comes back to the table. So when the pending ops also create one there, the index
  # has to be one no change could have asked: not covering a column the change at hand
  # converts or fills, and with no type change, fill or enum rebuild on its table before its
  # removal. Any unique index on the table and any such change count, whatever their columns -
  # following columns through the renames would buy a release that swaps one unique key for
  # another while converting one of them, which can update its rows instead.
  defp removed_later?(index, table, covered?, later_ops) do
    initial = %{index: index, removed?: false, table: table, unique?: false, written?: covered?}
    walked = Enum.reduce_while(later_ops, initial, &follow_index/2)

    walked.removed? and not (walked.written? and walked.unique?)
  end

  defp run_context do
    %{
      otp_app: Atom.to_string(Reflection.otp_app()),
      env: Atom.to_string(Hologram.env()),
      hologram_version: to_string(Application.spec(:hologram, :vsn)),
      timestamp: DateTime.utc_now(:microsecond)
    }
  end

  # The not-covered check is pure, so it runs BEFORE the lock is taken: a deploy whose model
  # never became migrations refuses without first making the fleet queue for the privilege.
  # Everything after it touches the schema and runs on the locked session - unless a read-only
  # look finds nothing to do (see up_to_date?/3), which is every boot of a deploy but the first.
  defp run_migrations(migrations, current_model, context) do
    check_covered!(migrations, current_model)

    mapping = Mapper.derive_from_model!(current_model)

    if !up_to_date?(migrations, mapping, context) do
      with_migration_connection(fn ->
        take_boot_key()
        acquire_migration_lock()

        run_locked(migrations, mapping, context)
      end)
    end

    :ok
  end

  defp run_locked(migrations, mapping, context) do
    {:ok, upgraded} =
      Connection.transaction(fn ->
        ensure_managed!(context)
        SchemaReconciler.upgrade_system_tables!(context)
      end)

    SchemaReconciler.log_system_upgrades(upgraded)

    applied = applied_versions()

    pre_model =
      migrations
      |> Enum.filter(&(&1.version in applied))
      |> Enum.reduce(Model.empty(), &Model.fold(&2, &1.ops))

    history_known? = known_history?(migrations, applied)

    if history_known?, do: apply_renames(pre_model)

    pending = pending(migrations, applied)

    create_applied_indexes(migrations, applied, pending, pre_model)

    apply_pending(pending, pre_model, context)

    if history_known? do
      repair_indexes(mapping)
      check_drift!(mapping)
    else
      converge_for_unknown_chain(mapping)
    end
  end

  # Whether the database is claimed for this app and env, has its system tables at the running
  # layout, has every migration of the chain applied, no model index missing or invalid, and no
  # drift - what the locked procedure would end with, so the boot skips it, and a node never waits
  # for the lock behind another node's index builds (see Hologram.DB.IndexBuilder). Read-only, so
  # taking no lock is safe: a node seeing a state another node is changing at that moment finds
  # something to do, or finds it already done. Anything it can't read - a virgin database, another
  # app's, a newer layout - is something to do, which the locked procedure claims or refuses.
  #
  # The invalid indexes are read last: a build in flight lists its index as present, invalid, from
  # its first moment, and an index only goes from invalid to valid, so one the reads before found
  # standing is either still invalid then, or built.
  defp up_to_date?(migrations, mapping, context) do
    hologram_schemas() == Enum.sort([Mapper.data_schema(), Mapper.system_schema()]) and
      check_marker!(context) == :managed and
      SchemaReconciler.pending_system_upgrades(context) == [] and
      pending(migrations, applied_versions()) == [] and
      missing_indexes(mapping) == [] and drift_ops(mapping) == [] and invalid_indexes() == []
  rescue
    _error -> false
  end

  # A connection lost here ends the session, which the next statement, or the exit the session
  # sends, reports.
  defp apply_keepalives do
    case Connection.query(Config.keepalive_statement()) do
      {:ok, _result} -> :ok
      {:error, %DBConnection.ConnectionError{}} -> :ok
      {:error, error} -> Config.warn_keepalives_refused(error)
    end
  end

  # Never let go by hand: it frees with the session, as the migration lock the boot takes does.
  defp take_boot_key do
    {:ok, %{rows: [[true]]}} =
      Connection.query("SELECT pg_try_advisory_lock_shared($1)", [@boot_lock_key])

    :ok
  end

  defp try_migration_lock? do
    {:ok, %{rows: [[acquired?]]}} =
      Connection.query("SELECT pg_try_advisory_lock($1)", [@advisory_lock_key])

    acquired?
  end
end
