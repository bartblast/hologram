defmodule Hologram.Database.SchemaReconciler do
  @moduledoc false

  alias Hologram.Database.Connection

  # Control-plane bookkeeping DDL - static and framework-owned, never model-derived.
  # The database table is the managed-database marker (single row, maintained by
  # write_marker/1) - the schema_object table is the managed-object registry.
  @system_statements [
    """
    CREATE TABLE "hologram_system"."database" (
      "otp_app" text NOT NULL,
      "env" text NOT NULL,
      "managed_by" text NOT NULL,
      "hologram_version" text NOT NULL,
      "last_reconciled_at" timestamptz NOT NULL
    )
    """,
    """
    CREATE TABLE "hologram_system"."schema_object" (
      "kind" text NOT NULL,
      "parent" text NOT NULL,
      "name" text NOT NULL,
      PRIMARY KEY ("kind", "parent", "name")
    )
    """
  ]

  @doc """
  Creates the control-plane bookkeeping tables in the hologram_system schema.
  """
  @spec create_system_tables() :: :ok
  def create_system_tables do
    Enum.each(@system_statements, fn statement ->
      {:ok, _result} = Connection.query(statement)
    end)

    :ok
  end

  @doc """
  Ensures the connected database is managed by schema reconciliation, claiming it when
  virgin - runs in the caller's transaction.

  A database containing neither Hologram schema is virgin (other schemas may exist -
  claiming touches nothing outside the two Hologram schemas): both schemas, the
  bookkeeping tables, and the marker are created, and :claimed is returned. A database
  whose marker matches the given context (:otp_app, :env, :hologram_version, and
  :timestamp - the latter two used when claiming) returns :managed. Every other state
  raises with a specific message: Hologram schemas without a marker, a marker belonging
  to another app or env, or a database managed by migrations.
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
  Returns the managed-database marker, or nil when none has been written.

  The marker is a map with :otp_app, :env, and :managed_by (the guard facts, as
  strings) plus :hologram_version and :last_reconciled_at (diagnostics).
  """
  @spec read_marker() :: %{atom => any} | nil
  def read_marker do
    statement = """
    SELECT "otp_app", "env", "managed_by", "hologram_version", "last_reconciled_at"
    FROM "hologram_system"."database"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    case rows do
      [] ->
        nil

      [[otp_app, env, managed_by, hologram_version, last_reconciled_at]] ->
        %{
          otp_app: otp_app,
          env: env,
          managed_by: managed_by,
          hologram_version: hologram_version,
          last_reconciled_at: last_reconciled_at
        }
    end
  end

  @doc """
  Returns the managed-object registry as a set of {kind, parent, name} tuples - kind is
  one of :table, :column, :constraint, :index, or :enum_type, and parent is the owning
  table name (an empty string for standalone objects: tables and enum types).
  """
  @spec registry() :: MapSet.t()
  def registry do
    statement = ~s(SELECT "kind", "parent", "name" FROM "hologram_system"."schema_object")

    {:ok, %{rows: rows}} = Connection.query(statement)

    MapSet.new(rows, fn [kind, parent, name] ->
      {String.to_existing_atom(kind), parent, name}
    end)
  end

  @doc """
  Applies the given change ops to the managed-object registry, in the caller's
  transaction.

  Create and add ops register the objects they produce (a created table registers
  itself, its columns, and its primary key constraint) - drop ops deregister them (a
  dropped table takes everything parented to it) - a constraint rename updates the
  registered name. Ops that change an object without changing its identity (column
  alterations, enum value changes, rebuilds) leave the registry untouched.
  Registration is idempotent - stale rows from out-of-contract edits never fail it.
  """
  @spec update_registry(list(%{atom => any})) :: :ok
  def update_registry(ops) do
    Enum.each(ops, &record_op/1)
  end

  @doc """
  Writes the given marker as the single row of the managed-database marker table,
  replacing any previous row.
  """
  @spec write_marker(%{atom => any}) :: :ok
  def write_marker(marker) do
    {:ok, _result} = Connection.query(~s(DELETE FROM "hologram_system"."database"))

    insert_statement = """
    INSERT INTO "hologram_system"."database"
      ("otp_app", "env", "managed_by", "hologram_version", "last_reconciled_at")
    VALUES ($1, $2, $3, $4, $5)
    """

    params = [
      marker.otp_app,
      marker.env,
      marker.managed_by,
      marker.hologram_version,
      marker.last_reconciled_at
    ]

    {:ok, _result} = Connection.query(insert_statement, params)

    :ok
  end

  defp check_marker!(context) do
    if not marker_table_exists?() do
      raise_not_managed!()
    end

    marker = read_marker()

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

      marker.managed_by != "reconciliation" ->
        raise "the configured database is managed by #{marker.managed_by} - " <>
                "schema reconciliation never touches it"

      true ->
        :managed
    end
  end

  defp claim(context) do
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

    create_system_tables()

    write_marker(%{
      otp_app: context.otp_app,
      env: context.env,
      managed_by: "reconciliation",
      hologram_version: context.hologram_version,
      last_reconciled_at: context.timestamp
    })

    :claimed
  end

  defp deregister(kind, parent, name) do
    statement = """
    DELETE FROM "hologram_system"."schema_object"
    WHERE "kind" = $1 AND "parent" = $2 AND "name" = $3
    """

    {:ok, _result} = Connection.query(statement, [Atom.to_string(kind), parent, name])

    :ok
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

  defp marker_table_exists? do
    statement = """
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hologram_system' AND c.relname = 'database' AND c.relkind = 'r'
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    rows != []
  end

  defp raise_not_managed! do
    raise "the configured database contains Hologram schemas but no managed-database " <>
            "marker - it is not managed by schema reconciliation - drop the " <>
            ~s("hologram_system" and "hologram_data" schemas or point the config ) <>
            "at another database"
  end

  defp record_op(%{op: :add_column} = op), do: register(:column, op.table, op.column)

  defp record_op(%{op: :add_enum_value}), do: :ok

  defp record_op(%{op: :add_foreign_key} = op), do: register(:constraint, op.table, op.constraint)

  defp record_op(%{op: :alter_column}), do: :ok

  defp record_op(%{op: :create_enum_type} = op), do: register(:enum_type, "", op.enum_type)

  defp record_op(%{op: :create_index} = op), do: register(:index, op.table, op.index)

  defp record_op(%{op: :create_table} = op) do
    register(:table, "", op.table)

    op.columns
    |> Map.keys()
    |> Enum.each(&register(:column, op.table, &1))

    register(:constraint, op.table, op.primary_key.constraint)
  end

  defp record_op(%{op: :drop_column} = op), do: deregister(:column, op.table, op.column)

  defp record_op(%{op: :drop_enum_type} = op), do: deregister(:enum_type, "", op.enum_type)

  defp record_op(%{op: :drop_foreign_key} = op) do
    deregister(:constraint, op.table, op.constraint)
  end

  defp record_op(%{op: :drop_index} = op) do
    statement = """
    DELETE FROM "hologram_system"."schema_object"
    WHERE "kind" = 'index' AND "name" = $1
    """

    {:ok, _result} = Connection.query(statement, [op.index])

    :ok
  end

  defp record_op(%{op: :drop_table} = op) do
    statement = """
    DELETE FROM "hologram_system"."schema_object"
    WHERE ("kind" = 'table' AND "name" = $1) OR "parent" = $1
    """

    {:ok, _result} = Connection.query(statement, [op.table])

    :ok
  end

  defp record_op(%{op: :rebuild_enum_type}), do: :ok

  defp record_op(%{op: :rename_constraint} = op) do
    statement = """
    UPDATE "hologram_system"."schema_object"
    SET "name" = $1
    WHERE "kind" = 'constraint' AND "parent" = $2 AND "name" = $3
    """

    {:ok, _result} = Connection.query(statement, [op.to, op.table, op.from])

    :ok
  end

  defp record_op(%{op: :rename_enum_value}), do: :ok

  defp register(kind, parent, name) do
    statement = """
    INSERT INTO "hologram_system"."schema_object" ("kind", "parent", "name")
    VALUES ($1, $2, $3)
    ON CONFLICT DO NOTHING
    """

    {:ok, _result} = Connection.query(statement, [Atom.to_string(kind), parent, name])

    :ok
  end
end
