defmodule Hologram.Migrator do
  @moduledoc false

  alias Hologram.DB.Connection
  alias Hologram.DB.SchemaReconciler

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
