defmodule Hologram.Migrator do
  @moduledoc false

  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Preflight
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Migration.Renderer

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
      execute_statements(Enum.flat_map(render.tail, &DDL.statements/1))
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
    record_applied(version, context.timestamp)

    :applied
  end

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

  defp execute_statements(statements) do
    Enum.each(statements, fn statement ->
      {:ok, _result} = Connection.query(statement)
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

  defp raise_not_managed! do
    raise "the configured database contains Hologram schemas but no managed-database " <>
            "marker - it is not managed by migrations - drop the " <>
            ~s("hologram_system" and "hologram_data" schemas or point the config ) <>
            "at another database"
  end
end
