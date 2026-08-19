defmodule Hologram.Migrator do
  @moduledoc false

  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Preflight
  alias Hologram.DB.Schema
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Entity.Model
  alias Hologram.Migration.Loader
  alias Hologram.Migration.Renderer
  alias Hologram.Reflection

  # Fixed application-defined key for pg_advisory_xact_lock - serializes the appliers of
  # a deploy, whichever node gets there first. The value is frozen forever: a different
  # key breaks mutual exclusion across Hologram versions, so it must survive any code
  # move or rename. Provenance (for uniqueness, not for re-derivation): first 8 bytes of
  # md5("hologram_migrations") as a signed int64.
  @advisory_lock_key -335_777_576_117_788_795

  # A key of its own, and the separation is what keeps a deploy from deadlocking itself. A
  # concurrent index build cannot run inside a transaction, so it holds a SESSION lock - while
  # every applier waits for its lock INSIDE one. Share one key between them and a node building
  # an index leaves the others sitting in open transactions waiting for it, which is the one
  # thing a concurrent build cannot outlast: it waits for every transaction that could see the
  # table, so it waits for them, and they wait for it. Frozen forever for the same reason as the
  # key above. Provenance (for uniqueness, not for re-derivation): first 8 bytes of
  # md5("hologram_index_repair") as a signed int64.
  #
  # EVERY concurrent index build in this module runs under this key - the repair path and the
  # applier's tail alike. Two concurrent builds on one relation deadlock each other directly
  # (each waits on the other's virtual transaction), so a builder this key does not cover is a
  # deadlock on every deploy where two nodes reach their builds together.
  #
  # Taken ONLY with pg_try_advisory_lock, never pg_advisory_lock: a session queued on the
  # blocking form holds a virtual transaction for as long as it waits, and a concurrent build
  # waits on every virtual transaction that could see the table - so a queued waiter and the
  # builder it waits for deadlock. A loser polls instead.
  @index_advisory_lock_key 6_059_159_047_318_510_073

  # How often a node that missed the index lock looks again. A politeness knob, not a
  # correctness bound - the loop exits by the work being done or by the freed lock, never
  # by a deadline.
  @index_repair_poll_interval_ms 1_000

  @managed_by "migrations"

  @doc """
  Returns the versions of the migrations the connected database has applied.
  """
  @spec applied_versions() :: MapSet.t()
  def applied_versions do
    statement = ~s(SELECT "version" FROM "hologram_system"."migration")

    {:ok, %{rows: rows}} = Connection.query(statement)

    MapSet.new(rows, fn [version] -> version end)
  end

  @doc """
  Applies the given migrations to the connected database, one transaction each, and
  returns the model the last of them leaves behind.

  A file's statements and its bookkeeping row commit together, so the record can never
  disagree with the schema, and a failure leaves the earlier files applied - every
  inter-file state is a reviewed historical model state, which makes file boundaries the
  right transaction boundaries. An advisory lock serializes the appliers of a deploy: the
  first node does the work, the rest wait, re-read the bookkeeping inside their own
  transaction, and find the file already applied. Index builds that cannot run inside a
  transaction follow after the commit.

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
  skipped or CI was.
  """
  @spec check_covered!(list(%{atom => any}), %{atom => any}) :: :ok
  def check_covered!(migrations, current_model) do
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

  The query-derived artifacts are the one carve-out: they follow the registered queries,
  not the model, and ride no migration - their ops are skipped rather than reported.
  """
  @spec check_drift!(%{module => %{atom => any}}) :: :ok
  def check_drift!(mapping) do
    drift_ops =
      Introspection.schema()
      |> Schema.diff(Schema.from_mapping(mapping))
      |> Enum.reject(&artifact_op?(&1, mapping))

    if drift_ops != [] do
      lines = Enum.map_join(drift_ops, "\n", &"  * #{describe_difference(&1)}")

      raise "schema drift detected - the database does not match the model:\n" <>
              lines <>
              "\nhologram_data is model-managed - restore what is missing, remove what " <>
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

  @doc """
  Ensures the connected database is managed by migrations, claiming it when virgin -
  runs in the caller's transaction.

  A database containing neither Hologram schema is virgin: both schemas, the bookkeeping
  tables, and the marker are created, and :claimed is returned. A database whose marker
  matches the given context returns :managed. Every other state raises with a specific
  message: Hologram schemas without a marker, a marker belonging to another app or env,
  or a database managed by schema reconciliation - dev's mechanism, which never shares a
  database with production.

  The advisory lock the appliers share is taken first, because a virgin database is the
  one state every node of a deploy resolves the same way: without it they all read "no
  schemas" and all run CREATE SCHEMA, and the losers of that race fail their boot. Held
  until the caller's transaction ends, so the claim is complete before the next node
  looks - which then finds the marker and returns :managed.
  """
  @spec ensure_managed!(%{atom => any}) :: :claimed | :managed
  def ensure_managed!(context) do
    {:ok, _result} = Connection.query("SELECT pg_advisory_xact_lock($1)", [@advisory_lock_key])

    case hologram_schemas() do
      [] -> claim(context)
      ["hologram_data", "hologram_system"] -> check_marker!(context)
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
  Converges the connected database's query-derived artifacts - the `_$sort` companion
  columns of the registered queries - to the given mapping, and returns the applied ops.

  The artifact set changes with every app build, independently of the model, so it rides
  no migration: the enriched mapping is the target, missing companions are added and
  orphaned ones dropped, and everything else in the diff is left alone. The backfill of
  an added companion is the caller's, reading the returned ops. The marker and the
  applied-migrations record stay untouched.
  """
  @spec reconcile_artifacts(%{module => %{atom => any}}) :: list(%{atom => any})
  def reconcile_artifacts(mapping) do
    {:ok, ops} =
      Connection.transaction(fn ->
        {:ok, _result} =
          Connection.query("SELECT pg_advisory_xact_lock($1)", [@advisory_lock_key])

        ops =
          Introspection.schema()
          |> Schema.diff(Schema.from_mapping(mapping))
          |> Enum.filter(&artifact_op?(&1, mapping))

        Enum.each(ops, &apply_op(&1, mapping))

        ops
      end)

    ops
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
    INSERT INTO "hologram_system"."migration" ("version", "applied_at", "model_hash")
    VALUES ($1, $2, $3)
    """

    {:ok, _result} = Connection.query(statement, [version, timestamp, model_hash])

    :ok
  end

  @doc """
  Converges the indexes the given mapping derives - rebuilding the ones PostgreSQL left
  invalid and creating the ones that are absent - and returns :ok.

  Index builds are the one part of a migration that cannot ride its transaction, so they
  run after the file commits. A node dying in that window leaves the file recorded as
  applied and its index unfinished: invalid when the build had started, absent when it
  had not. Neither heals on its own - the file is no longer pending, so no later boot
  revisits it, and an invalid index still reads as present to the drift check.

  Indexes are the one object this repairs rather than reports. They carry no data, the
  model is their only author, and refusing instead would wedge every node of a fleet
  behind a state nothing can reach on its own. Everything else the drift check still
  refuses.

  The work runs on a connection of its own, guarded by a session-scoped advisory lock: a
  concurrent build cannot run inside a transaction, and nodes building the same index at
  the same moment deadlock each other.

  The lock is TRIED, never waited on. A concurrent build waits for every open transaction
  that could see the table, and a node queued on the lock is exactly that - its blocked
  SELECT holds a virtual transaction for as long as it queues - so a polite waiter and the
  builder deadlock each other, each holding what the other needs. A node that misses the
  lock polls the catalog instead: each check is a millisecond statement that opens and
  closes between the build's waits, jamming nothing. It leaves when the work is done, or
  acquires the lock and does the work itself when the holder dies - a session lock frees
  with its session, so a crashed builder cannot strand the fleet, and the half-built index
  it leaves reads as invalid and is rebuilt by whoever takes over.

  That lock is NOT the one the appliers share. An applier waits for its lock inside a
  transaction, so one key for both would hand the builder-versus-waiter deadlock to every
  deploy rather than to unlucky timing.
  """
  @spec repair_indexes(%{module => %{atom => any}}) :: :ok
  def repair_indexes(mapping) do
    if invalid_indexes() == [] and missing_indexes(mapping) == [] do
      :ok
    else
      with_index_build_connection(fn -> rebuild_and_create_indexes(mapping) end)
    end
  end

  @doc """
  Applies the pending migrations of the project's migrations directory to the connected
  database as the current model's history.

  Idempotent, so it is safe to run ahead of boot as a release step (`bin/app eval
  "Hologram.Migrator.run()"`) - an apply that already ran leaves nothing pending, and
  the boot-time apply passes through. Same mechanism either way, nothing to configure.
  """
  @spec run() :: :ok
  def run do
    migrations = Loader.load_dir!(Loader.migrations_dir())
    current_model = Model.from_modules(Reflection.list_entities(), Reflection.list_roles())

    run(migrations, current_model, run_context())
  end

  @doc """
  Applies the given migrations' pending suffix to the connected database as the given
  model's history.

  The not-covered check runs first, before any database access - then the guard claims
  or verifies the database, and the pending files apply from the model the applied ones
  produce.
  """
  @spec run(list(%{atom => any}), %{atom => any}, %{atom => any}) :: :ok
  def run(migrations, current_model, context) do
    Connection.with_timeout(:infinity, fn ->
      run_migrations(migrations, current_model, context)
    end)
  end

  defp apply_migration(migration, model, context) do
    render = Renderer.render(migration.ops, model)

    {:ok, status} =
      Connection.transaction(fn ->
        {:ok, _result} =
          Connection.query("SELECT pg_advisory_xact_lock($1)", [@advisory_lock_key])

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

  # Acquired by polling, never by queuing - see @index_advisory_lock_key. The work behind the
  # lock is ours to do, so unlike the repair path's loser there is no done-by-someone-else exit:
  # the loop ends by winning the lock.
  defp acquire_index_build_lock do
    unless try_index_advisory_lock?() do
      Process.sleep(@index_repair_poll_interval_ms)
      acquire_index_build_lock()
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

    # The tail's checks run here, against the columns the statements above just created
    # and before anything commits: a file whose index cannot be built does not apply at
    # all, rather than committing and failing afterwards.
    Preflight.run!(render.tail, actual, mapping)

    record_applied(version, context.timestamp, Model.hash(render.post_model))

    :applied
  end

  # The query-derived artifacts are outside the model's jurisdiction: check_drift!/1
  # skips them and reconcile_artifacts/1 converges them. An added companion is
  # recognized by its derivation source in the mapping - a dropped orphan is absent
  # from the mapping, so its `_$sort` suffix decides, and only sort companions carry it.
  # TODO: query-derived indexes cannot partition by suffix - `_$idx` is shared with the
  # model's foreign-key indexes - extend the source-based split when they arrive.
  defp artifact_op?(%{op: :add_column} = op, mapping) do
    match?(%{source: {:sort_key, _name}}, mapping_column(mapping, op.table, op.column))
  end

  defp artifact_op?(%{op: :drop_column} = op, _mapping) do
    String.ends_with?(op.column, "_$sort")
  end

  defp artifact_op?(_op, _mapping), do: false

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
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

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
  defp execute_tail_op(%{op: :create_index} = op) do
    drop_invalid_index(op.index)

    if count_result(DDL.built_index_check_statement(op.index)) == 0 do
      execute_statements(DDL.statements(op))
    end
  end

  # A tail op is a concurrent index build, so it is a BUILDER and runs like the other one: on a
  # session of its own (the pool can put the lock and the statement on different connections),
  # under the builder lock. Unlocked, another node that finds the chain applied reaches its
  # repair while this build is mid-flight, reads the half-built index as broken, and REINDEXes
  # it - two concurrent builds on one relation, waiting on each other's virtual transactions.
  # The lock is also what tells that node in-progress apart from abandoned: it polls until this
  # session is done and then finds nothing to repair.
  defp execute_tail_ops(tail) do
    with_index_build_connection(fn ->
      acquire_index_build_lock()

      try do
        Enum.each(tail, &execute_tail_op/1)
      after
        {:ok, _result} =
          Connection.query("SELECT pg_advisory_unlock($1)", [@index_advisory_lock_key])
      end
    end)
  end

  defp fill_column(table, column, encoded_value) do
    fill_statement = DDL.fill_statement(table, column)

    {:ok, _result} = Connection.query(fill_statement, [encoded_value])
  end

  defp hologram_schemas do
    statement = """
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname IN ('hologram_data', 'hologram_system')
    ORDER BY nspname
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [name] -> name end)
  end

  defp invalid_indexes do
    {:ok, %{rows: rows}} = Connection.query(DDL.invalid_indexes_statement())

    Enum.map(rows, fn [index] -> index end)
  end

  defp mapping_column(mapping, table, column_name) do
    entity_mapping =
      mapping
      |> Map.values()
      |> Enum.find(&(&1.table == table))

    entity_mapping && Enum.find(entity_mapping.columns, &(&1.name == column_name))
  end

  defp raise_not_managed! do
    raise "the configured database contains Hologram schemas but no managed-database " <>
            "marker - it is not managed by migrations - drop the " <>
            ~s("hologram_system" and "hologram_data" schemas or point the config ) <>
            "at another database"
  end

  # Re-read inside the lock: the node that held it before may have finished everything
  # already, which is the common case for every node of a deploy but the first.
  # Only what the model derives: an index the mapping does not name is drift for the
  # check to report, never something to create. A table the database does not have is
  # drift as well, and the pattern skips it - creating its indexes would raise a relation
  # error here, before check_drift!/1 gets to name the missing table as the cause.
  defp missing_indexes(mapping) do
    actual = Introspection.schema()
    expected = Schema.from_mapping(mapping)

    for {table, %{indexes: indexes}} <- expected.tables,
        %{indexes: standing} <- [actual.tables[table]],
        {index, definition} <- indexes,
        not Map.has_key?(standing, index) do
      %{
        op: :create_index,
        table: table,
        index: index,
        columns: definition.columns,
        nulls_distinct: definition.nulls_distinct,
        unique: definition.unique
      }
    end
  end

  defp rebuild_and_create_indexes(mapping) do
    if try_index_advisory_lock?() do
      try do
        Enum.each(invalid_indexes(), &rebuild_index/1)

        mapping
        |> missing_indexes()
        |> Enum.each(&create_index_concurrently/1)
      after
        {:ok, _result} =
          Connection.query("SELECT pg_advisory_unlock($1)", [@index_advisory_lock_key])
      end

      :ok
    else
      await_index_repair(mapping)
    end
  end

  # Another node holds the lock and is doing this work. Polling the catalog is the one way to
  # wait that cannot jam it - and re-trying the lock each round is what takes over when the
  # holder dies, since a session lock frees with its session.
  defp await_index_repair(mapping) do
    Process.sleep(@index_repair_poll_interval_ms)

    if invalid_indexes() == [] and missing_indexes(mapping) == [] do
      :ok
    else
      rebuild_and_create_indexes(mapping)
    end
  end

  defp try_index_advisory_lock? do
    {:ok, %{rows: [[acquired?]]}} =
      Connection.query("SELECT pg_try_advisory_lock($1)", [@index_advisory_lock_key])

    acquired?
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

  defp run_migrations(migrations, current_model, context) do
    check_covered!(migrations, current_model)

    {:ok, _status} = Connection.transaction(fn -> ensure_managed!(context) end)

    applied = applied_versions()

    pre_model =
      migrations
      |> Enum.filter(&(&1.version in applied))
      |> Enum.reduce(Model.empty(), &Model.fold(&2, &1.ops))

    migrations
    |> pending(applied)
    |> apply_pending(pre_model, context)

    mapping = Mapper.derive_from_model!(current_model)

    repair_indexes(mapping)

    # The query-derived companions are not converged here - they follow the registered
    # queries, which are not known until the query cache boots, and the drift check
    # skips their ops rather than reporting them.
    check_drift!(mapping)

    :ok
  end

  # Opened against the database currently connected rather than the configured one:
  # they are the same at boot, and following the caller keeps the builds honest wherever
  # else the applier is pointed. A session of its own, because the builder lock is
  # session-scoped and the pool can put the lock and the build on different connections.
  defp with_index_build_connection(fun) do
    {:ok, %{rows: [[database]]}} = Connection.query("SELECT current_database()")
    connection_opts = Config.connection_opts(database: database)
    {:ok, connection_pid} = Postgrex.start_link(connection_opts)

    try do
      Connection.with_connection(connection_pid, fun)
    after
      GenServer.stop(connection_pid)
    end
  end
end
