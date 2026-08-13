defmodule Hologram.Migrator do
  @moduledoc false

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
  @spec apply_pending(list(%{atom => any}), %{atom => map}, %{atom => any}) :: %{atom => map}
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
  @spec check_covered!(list(%{atom => any}), %{atom => map}) :: :ok
  def check_covered!(migrations, current_model) do
    replayed = Enum.reduce(migrations, Model.empty(), &Model.fold(&2, &1.ops))

    if replayed != current_model do
      differing = differing_names(replayed, current_model)
      names = Enum.map_join(differing, ", ", &inspect/1)

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
      lines = Enum.map_join(drift_ops, "\n", &"  * #{describe_drift(&1)}")

      raise "schema drift detected - the database does not match the model:\n" <>
              lines <>
              "\nhologram_data is model-managed - restore what is missing, remove what " <>
              "was added by hand, or express the change as a migration"
    end

    :ok
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
  """
  @spec ensure_managed!(%{atom => any}) :: :claimed | :managed
  def ensure_managed!(context) do
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

        Enum.each(ops, &apply_op/1)

        ops
      end)

    ops
  end

  @doc """
  Records the given migration version as applied at the given time, in the caller's
  transaction.
  """
  @spec record_applied(String.t(), DateTime.t()) :: :ok
  def record_applied(version, timestamp) do
    statement = """
    INSERT INTO "hologram_system"."migration" ("version", "applied_at")
    VALUES ($1, $2)
    """

    {:ok, _result} = Connection.query(statement, [version, timestamp])

    :ok
  end

  @doc """
  Applies the pending migrations of the project's migrations directory to the connected
  database as the current model's history.

  The public entry a deploy pipeline may call before rolling nodes (`bin/app eval
  "Hologram.Migrator.run()"`) - the boot-time apply then finds nothing pending. Same
  mechanism either way, nothing to configure.
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
  @spec run(list(%{atom => any}), %{atom => map}, %{atom => any}) :: :ok
  def run(migrations, current_model, context) do
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

    # The query-derived companions are not converged here - they follow the registered
    # queries, which are not known until the query cache boots, and the drift check
    # skips their ops rather than reporting them.
    check_drift!(Mapper.derive_from_model!(current_model))

    :ok
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

    if status == :applied do
      Enum.each(render.tail, &execute_tail_op/1)
    end

    render.post_model
  end

  # A required column arriving with a backfill is added nullable, filled, then tightened -
  # the value never travels in the DDL, and the rows that predate the column receive it.
  defp apply_op(%{op: :add_column, backfill: value} = op) do
    nullable_definition = %{op.definition | null: true}

    execute_statements(DDL.statements(%{op | definition: nullable_definition}))
    fill_column(op.table, op.column, value)

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

  defp apply_op(op), do: execute_statements(DDL.statements(op))

  defp apply_transactional(render, version, context) do
    actual = Introspection.schema()
    mapping = Mapper.derive_from_model!(render.post_model)

    Preflight.run!(render.transactional, actual, mapping)
    Enum.each(render.transactional, &apply_op/1)

    # The tail's checks run here, against the columns the statements above just created
    # and before anything commits: a file whose index cannot be built does not apply at
    # all, rather than committing and failing afterwards.
    Preflight.run!(render.tail, actual, mapping)

    record_applied(version, context.timestamp)

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

  defp describe_drift(%{op: :add_column} = op) do
    ~s(column "#{op.column}" on table "#{op.table}" declared by the model is missing)
  end

  defp describe_drift(%{op: :add_enum_value} = op) do
    ~s(enum type "#{op.enum_type}" is missing the declared value '#{op.value}')
  end

  defp describe_drift(%{op: :add_foreign_key} = op) do
    ~s(constraint "#{op.constraint}" on table "#{op.table}" declared by the model is missing)
  end

  defp describe_drift(%{op: :alter_column} = op) do
    ~s(column "#{op.column}" on table "#{op.table}" does not match its declaration)
  end

  defp describe_drift(%{op: :create_enum_type} = op) do
    ~s(enum type "#{op.enum_type}" declared by the model is missing)
  end

  defp describe_drift(%{op: :create_index} = op) do
    ~s(index "#{op.index}" declared by the model is missing)
  end

  defp describe_drift(%{op: :create_table} = op) do
    ~s(table "#{op.table}" declared by the model is missing)
  end

  defp describe_drift(%{op: :drop_column} = op) do
    ~s(column "#{op.column}" on table "#{op.table}" is not derived from the model)
  end

  defp describe_drift(%{op: :drop_enum_type} = op) do
    ~s(enum type "#{op.enum_type}" is not derived from the model)
  end

  defp describe_drift(%{op: :drop_foreign_key} = op) do
    ~s(constraint "#{op.constraint}" on table "#{op.table}" is not derived from the model)
  end

  defp describe_drift(%{op: :drop_index} = op) do
    ~s(index "#{op.index}" is not derived from the model)
  end

  defp describe_drift(%{op: :drop_table} = op) do
    ~s(table "#{op.table}" is not derived from the model)
  end

  defp describe_drift(%{op: :rebuild_enum_type} = op) do
    ~s(enum type "#{op.enum_type}" does not hold the declared values in their order)
  end

  defp describe_drift(%{op: :rename_constraint} = op) do
    ~s(constraint "#{op.from}" on table "#{op.table}" is named outside the derived scheme)
  end

  defp differing_names(replayed, current) do
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

    Enum.sort(entity_names ++ role_names)
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

  defp execute_tail_op(%{op: :create_index} = op) do
    drop_invalid_index(op.index)

    execute_statements(DDL.statements(op))
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

  defp run_context do
    %{
      otp_app: Atom.to_string(Reflection.otp_app()),
      env: Atom.to_string(Hologram.env()),
      hologram_version: to_string(Application.spec(:hologram, :vsn)),
      timestamp: DateTime.utc_now(:microsecond)
    }
  end
end
