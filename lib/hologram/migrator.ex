defmodule Hologram.Migrator do
  @moduledoc false

  require Logger

  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Preflight
  alias Hologram.DB.Schema
  alias Hologram.DB.SchemaReconciler
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
  @advisory_lock_key -335_777_576_117_788_795

  # How often a node that missed the migration lock looks again. A politeness knob, not a
  # correctness bound - the loop exits by winning the lock, never by a deadline.
  @migration_lock_poll_interval_ms 1_000

  @managed_by "migrations"

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

  The managed-object registry is deliberately left alone - it is schema reconciliation's
  record of what it created, and a migration-managed database has no use for it.
  """
  @spec apply_pending(list(%{atom => any}), %{atom => any}, %{atom => any}) :: %{atom => any}
  def apply_pending(migrations, pre_model, context) do
    Enum.reduce(migrations, pre_model, &apply_migration(&1, &2, context))
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
  or a database managed by schema reconciliation - dev's mechanism, which never shares a
  database with production.

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
  refuses.

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
    if invalid_indexes() == [] and missing_indexes(mapping) == [] do
      :ok
    else
      rebuild_and_create_indexes(mapping)
    end
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
  or verifies the database, objects standing under names the current naming rule no
  longer derives are renamed (one info line each), and the pending files apply from the
  model the applied ones produce. The index repair and the drift check come last.
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

    {:ok, connection_pid} = Postgrex.start_link(connection_opts)

    try do
      Connection.with_connection(connection_pid, fn ->
        {:ok, _result} =
          Connection.query("""
          SELECT set_config(name, '0', false)
          FROM pg_catalog.pg_settings
          WHERE name IN ('lock_timeout', 'statement_timeout', 'transaction_timeout')
          """)

        fun.()
      end)
    after
      # A session already gone exits here, which would replace what the function raised.
      catch_exit_quietly(fn -> GenServer.stop(connection_pid) end)
    end
  end

  @doc """
  Runs the given function under the migration lock, taken on the current session by polling (see
  @advisory_lock_key in this module) and released once the function returns or raises, and
  returns what the function returns. For work beside the boot procedure that changes the schema,
  one step at a time - each step holds the lock no longer than it takes. Polls at the given
  interval, the boot's when absent: a caller polling more slowly than the boot most likely gives
  way to a booting node.
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
  defp apply_migration(migration, model, context) do
    render = Renderer.render(migration.ops, model)

    {:ok, status} =
      Connection.transaction(fn ->
        if migration.version in applied_versions() do
          :skipped
        else
          apply_transactional(render, migration.version, context)
        end
      end)

    if status == :applied and render.tail != [] do
      execute_tail_ops(render.tail)
    end

    render.post_model
  end

  # Acquired by polling, never by queuing - see @advisory_lock_key. The work behind the lock
  # is ours to do, so there is no done-by-someone-else exit: the loop ends by winning it.
  defp acquire_migration_lock(poll_interval_ms \\ @migration_lock_poll_interval_ms) do
    unless try_migration_lock?() do
      Process.sleep(poll_interval_ms)
      acquire_migration_lock(poll_interval_ms)
    end
  end

  defp apply_op(%{op: :add_column, backfill: value} = op, _mapping) do
    add_column_filled(op, value)
  end

  # A required column with no backfill takes its declared default, which is what schema
  # reconciliation does for the same declaration in dev - the two mechanisms have to leave
  # the same rows behind, not merely the same columns.
  defp apply_op(%{op: :add_column} = op, mapping) do
    fill =
      if op.definition.null,
        do: :none,
        else: Preflight.fill_value(mapping, op.table, op.column)

    case fill do
      :none -> execute_statements(DDL.statements(op))
      {:ok, encoded_value} -> add_column_filled(op, encoded_value)
    end
  end

  # A type change asks about the unique indexes standing over its column right before it
  # applies: two values can convert to one. It drops the plan's indexes over a column cast to
  # text then too. Both read the names a file's earlier ops leave behind, which are the ones the
  # database holds at this point.
  defp apply_op(%{op: :alter_column} = op, _mapping) do
    Preflight.check_cast!(op)
    drop_plan_indexes_cast_to_text(op)

    execute_statements(DDL.statements(op))
  end

  defp apply_op(op, _mapping), do: execute_statements(DDL.statements(op))

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

  defp apply_transactional(render, version, context) do
    actual = Introspection.schema()
    mapping = Mapper.derive_from_model!(render.post_model)

    Preflight.run!(render.transactional, actual, mapping)
    Enum.each(render.transactional, &apply_op(&1, mapping))

    # A companion this file adds is filled AFTER every op has applied, not at its own add:
    # the diff applies add_column before alter_column, so a source column being cast to
    # text in the same file still holds its old type when its companion lands.
    SchemaReconciler.backfill_companions!(render.transactional, mapping)

    # The tail's checks run here, against the schema the statements above just produced and
    # before anything commits: a file whose index cannot be built does not apply at all,
    # rather than committing and failing afterwards. The schema is read again on purpose - a
    # column this file adds and fills is absent from the one the file started from, and a
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
  # Only a node whose chain holds every applied version heals (see known_chain?/2). One that
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
        :managed
    end
  end

  # The one path that builds the system tables, and so the one that decides which columns a
  # database has forever: a database already claimed goes through check_marker!/1 above, which
  # reads the marker and changes nothing. So a column added here later - `model_hash` on the
  # migration table is one - reaches virgin databases only, and the first write that needs it
  # fails on one claimed before it existed.
  #
  # Deliberate while the data layer is unreleased, and owed at its first release together with the
  # bump it belongs to - see `@system_schema_version` in Hologram.DB.SchemaReconciler, which
  # carries the whole reasoning. Until then a stale database is dropped and recreated.
  defp claim(context) do
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "#{Mapper.system_schema()}"))
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "#{Mapper.data_schema()}"))

    SchemaReconciler.create_system_tables()

    SchemaReconciler.write_marker(%{
      otp_app: context.otp_app,
      env: context.env,
      managed_by: @managed_by,
      hologram_version: context.hologram_version,
      last_reconciled_at: context.timestamp
    })

    :claimed
  end

  defp count_result(statement) do
    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count
  end

  defp create_index_concurrently(op) do
    concurrent_op = Map.put(op, :concurrently, true)

    execute_statements(DDL.statements(concurrent_op))
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
  # invalid: it holds the name, serves no query, and every write maintains it. Clearing
  # it before building makes the tail safe to run again, so a crashed deploy retries
  # without anyone opening psql.
  defp drop_invalid_index(index) do
    if count_result(DDL.invalid_index_check_statement(index)) > 0 do
      execute_statements(DDL.statements(%{op: :drop_index, index: index}))
    end
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
  # CONCURRENTLY is not decided here: the renderer decides what belongs in the tail at all, and
  # what it decides IS concurrent - it stamps every op it puts there, because being unable to run
  # inside the migration's transaction is the whole reason the tail exists.
  defp execute_tail_op(%{op: :create_index} = op) do
    drop_invalid_index(op.index)

    if count_result(DDL.built_index_check_statement(op.index)) == 0 do
      execute_statements(DDL.statements(op))
    end
  end

  # Runs on the migration lock's session, which by now holds no open transaction - the file
  # committed above - which is what a concurrent build needs. The lock is already held and has
  # to be: unlocked, a node applying the NEXT file deadlocks against this build outright, and a
  # node reaching its own repair reads this half-built index as broken and REINDEXes it, which
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

  defp known_chain?(migrations, applied) do
    known_versions = MapSet.new(migrations, & &1.version)

    Enum.all?(applied, &MapSet.member?(known_versions, &1))
  end

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

  defp invalid_indexes do
    statement = DDL.invalid_indexes_statement(true)
    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [index] -> index end)
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

  defp rebuild_and_create_indexes(mapping) do
    Enum.each(invalid_indexes(), &rebuild_index/1)

    mapping
    |> missing_indexes()
    |> Enum.each(&create_index_concurrently/1)

    :ok
  end

  defp rebuild_index(index) do
    execute_statements([DDL.reindex_statement(index)])
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
        acquire_migration_lock()

        run_locked(migrations, mapping, context)
      end)
    end

    :ok
  end

  defp run_locked(migrations, mapping, context) do
    {:ok, _status} = Connection.transaction(fn -> ensure_managed!(context) end)

    applied = applied_versions()

    pre_model =
      migrations
      |> Enum.filter(&(&1.version in applied))
      |> Enum.reduce(Model.empty(), &Model.fold(&2, &1.ops))

    chain_known? = known_chain?(migrations, applied)

    if chain_known?, do: apply_renames(pre_model)

    migrations
    |> pending(applied)
    |> apply_pending(pre_model, context)

    if chain_known? do
      repair_indexes(mapping)
      check_drift!(mapping)
    else
      converge_for_unknown_chain(mapping)
    end
  end

  # Whether the database is claimed for this app and env, has every migration of the chain applied,
  # no model index missing or invalid, and no drift - what the locked procedure would end with, so
  # the boot skips it, and a node never waits for the lock behind another node's index builds (see
  # Hologram.DB.IndexBuilder). Read-only, so taking no lock is safe: a node seeing a state another
  # node is changing at that moment finds something to do, or finds it already done. Anything it
  # can't read - a virgin database, another app's - is something to do, which the locked procedure
  # claims or refuses.
  #
  # The invalid indexes are read last: a build in flight lists its index as present, invalid, from
  # its first moment, and an index only goes from invalid to valid, so one the reads before found
  # standing is either still invalid then, or built.
  defp up_to_date?(migrations, mapping, context) do
    hologram_schemas() == Enum.sort([Mapper.data_schema(), Mapper.system_schema()]) and
      check_marker!(context) == :managed and pending(migrations, applied_versions()) == [] and
      missing_indexes(mapping) == [] and drift_ops(mapping) == [] and invalid_indexes() == []
  rescue
    _error -> false
  end

  defp try_migration_lock? do
    {:ok, %{rows: [[acquired?]]}} =
      Connection.query("SELECT pg_try_advisory_lock($1)", [@advisory_lock_key])

    acquired?
  end
end
