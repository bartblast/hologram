defmodule Hologram.Database.SchemaReconciler do
  @moduledoc false

  require Logger

  alias Hologram.Database.Codec
  alias Hologram.Database.Connection
  alias Hologram.Database.DDL
  alias Hologram.Database.Introspection
  alias Hologram.Database.Schema

  # Fixed application-defined key for pg_advisory_xact_lock - serializes concurrent
  # reconciliations from multiple VMs against one database (the second waits, then
  # introspects the converged state and gets an empty diff). The value is frozen
  # forever: a different key breaks mutual exclusion across Hologram versions, so it
  # must survive any code move or rename. Provenance (for uniqueness, not for
  # re-derivation): first 8 bytes of md5("hologram_schema_reconciliation") as a
  # signed int64.
  @advisory_lock_key 4_787_000_136_577_093_832

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
  Converges the database schema to the given mapping and returns %{status:, ops:} -
  status is :claimed (virgin database) or :managed, ops are the applied change ops
  (empty when the schema already matched).

  The whole run is one crash-atomic transaction serialized by an advisory lock: guard
  check (claiming when virgin), introspect the actual schema, project the target from
  the mapping, diff, alien check (dropping an object the registry does not know fails
  loudly - hologram_data is model-managed), pre-flight data validation (transformations
  the existing rows cannot follow fail with the ways out before any DDL runs), render
  and apply the DDL, update the managed-object registry from the op stream, and refresh
  the marker (last_reconciled_at, hologram_version). After the transaction commits,
  each destructive action is logged as one concise line. The context carries :mapping
  plus the guard facts (:otp_app, :env) and the marker diagnostics (:hologram_version,
  :timestamp).
  """
  @spec reconcile(%{atom => any}) :: %{atom => any}
  def reconcile(context) do
    {:ok, result} =
      Connection.transaction(fn ->
        {:ok, _result} =
          Connection.query("SELECT pg_advisory_xact_lock($1)", [@advisory_lock_key])

        status = ensure_managed!(context)

        actual = Introspection.schema()
        target = Schema.from_mapping(context.mapping)
        ops = Schema.diff(actual, target)

        check_aliens!(ops, registry())
        preflight!(ops, actual, context.mapping)

        apply_ops(ops, context.mapping)
        update_registry(ops)
        write_marker(marker_from_context(context))

        %{status: status, ops: ops}
      end)

    log_destructive_ops(result.ops)

    result
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

  # A required add with a declared default applies as add-nullable, parameterized fill,
  # then tighten - so existing rows receive the default and the DDL never carries values.
  defp apply_op(%{op: :add_column} = op, mapping) do
    fill = if op.definition.null, do: :none, else: fill_value(mapping, op.table, op.column)

    case fill do
      :none ->
        execute_statements(DDL.statements(op))

      {:ok, encoded_value} ->
        nullable_definition = %{op.definition | null: true}
        execute_statements(DDL.statements(%{op | definition: nullable_definition}))
        fill_column(op.table, op.column, encoded_value)

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

  # Pure null-tightening with a declared default fills the NULLs first - a combined
  # type change never fills (the default holds a new-type value, the column still has
  # the old type), so pre-flight lets only NULL-free combined changes through.
  defp apply_op(%{op: :alter_column} = op, mapping) do
    fill =
      if op.before.null and not op.after.null and op.before.type == op.after.type do
        fill_value(mapping, op.table, op.column)
      else
        :none
      end

    case fill do
      :none -> :ok
      {:ok, encoded_value} -> fill_column(op.table, op.column, encoded_value)
    end

    execute_statements(DDL.statements(op))
  end

  defp apply_op(op, _mapping), do: execute_statements(DDL.statements(op))

  defp apply_ops(ops, mapping) do
    Enum.each(ops, &apply_op(&1, mapping))
  end

  defp check_alien!(%{op: :drop_column} = op, registry) do
    if {:column, op.table, op.column} not in registry do
      raise_alien!(~s(column "#{op.column}" on table "#{op.table}"))
    end
  end

  defp check_alien!(%{op: :drop_enum_type} = op, registry) do
    if {:enum_type, "", op.enum_type} not in registry do
      raise_alien!(~s(enum type "#{op.enum_type}"))
    end
  end

  defp check_alien!(%{op: :drop_foreign_key} = op, registry) do
    if {:constraint, op.table, op.constraint} not in registry do
      raise_alien!(~s(constraint "#{op.constraint}" on table "#{op.table}"))
    end
  end

  defp check_alien!(%{op: :drop_index} = op, registry) do
    index = op.index

    if not Enum.any?(registry, &match?({:index, _parent, ^index}, &1)) do
      raise_alien!(~s(index "#{op.index}"))
    end
  end

  defp check_alien!(%{op: :drop_table} = op, registry) do
    if {:table, "", op.table} not in registry do
      raise_alien!(~s(table "#{op.table}"))
    end
  end

  defp check_alien!(_op, _registry), do: :ok

  defp check_aliens!(ops, registry) do
    Enum.each(ops, &check_alien!(&1, registry))
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

  defp count_result(statement) do
    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count
  end

  defp deregister(kind, parent, name) do
    statement = """
    DELETE FROM "hologram_system"."schema_object"
    WHERE "kind" = $1 AND "parent" = $2 AND "name" = $3
    """

    {:ok, _result} = Connection.query(statement, [Atom.to_string(kind), parent, name])

    :ok
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

  defp fill_value(mapping, table, column_name) do
    entity_mapping =
      mapping
      |> Map.values()
      |> Enum.find(&(&1.table == table))

    column = entity_mapping && Enum.find(entity_mapping.columns, &(&1.name == column_name))

    case column do
      %{default: nil} -> :none
      %{default: default, type: type} -> {:ok, Codec.encode(default, type)}
      nil -> :none
    end
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

  defp log_destructive_op(%{op: :drop_column} = op) do
    Logger.info(~s(schema reconciliation dropped column "#{op.column}" on table "#{op.table}"))
  end

  defp log_destructive_op(%{op: :drop_enum_type} = op) do
    Logger.info(~s(schema reconciliation dropped enum type "#{op.enum_type}"))
  end

  defp log_destructive_op(%{op: :drop_table} = op) do
    Logger.info(~s(schema reconciliation dropped table "#{op.table}"))
  end

  defp log_destructive_op(%{op: :rebuild_enum_type} = op) do
    Logger.info(~s(schema reconciliation rebuilt enum type "#{op.enum_type}"))
  end

  defp log_destructive_op(_op), do: :ok

  defp log_destructive_ops(ops) do
    Enum.each(ops, &log_destructive_op/1)
  end

  defp marker_from_context(context) do
    %{
      otp_app: context.otp_app,
      env: context.env,
      managed_by: "reconciliation",
      hologram_version: context.hologram_version,
      last_reconciled_at: context.timestamp
    }
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

  defp pluralize_rows(1), do: "row"

  defp pluralize_rows(_count), do: "rows"

  defp pluralize_values([_value]), do: "value"

  defp pluralize_values(_values), do: "values"

  defp preflight!(ops, actual, mapping) do
    Enum.each(ops, &preflight_op!(&1, actual, mapping))
  end

  defp preflight_cast_rows!(op) do
    count =
      count_result(DDL.cast_check_statement(op.table, op.column, op.before.type, op.after.type))

    if count > 0 do
      raise ~s(#{count} #{pluralize_rows(count)} in "#{op.table}"."#{op.column}" ) <>
              "cannot convert from #{op.before.type} to #{op.after.type} - " <>
              "fix the data or remove the attribute and re-add it with the new type"
    end
  end

  defp preflight_null_tightening!(op, mapping) do
    fillable? =
      op.before.type == op.after.type and
        match?({:ok, _value}, fill_value(mapping, op.table, op.column))

    checked? = op.before.null and not op.after.null and not fillable?
    count = if checked?, do: count_result(DDL.null_check_statement(op.table, op.column)), else: 0

    if count > 0 do
      raise ~s(cannot make column "#{op.column}" on table "#{op.table}" required - ) <>
              "found #{count} #{pluralize_rows(count)} with NULL - " <>
              "declare a default:, keep the attribute optional:, or fix the data"
    end
  end

  defp preflight_op!(%{op: :add_column} = op, _actual, mapping) do
    checked? =
      not op.definition.null and
        not match?({:ok, _value}, fill_value(mapping, op.table, op.column))

    count = if checked?, do: count_result(DDL.rows_check_statement(op.table)), else: 0

    if count > 0 do
      raise ~s(cannot add required column "#{op.column}" to table "#{op.table}" - ) <>
              "#{count} existing #{pluralize_rows(count)} would have no value - " <>
              "declare a default:, make the attribute optional:, or clear the rows"
    end
  end

  defp preflight_op!(%{op: :alter_column} = op, _actual, mapping) do
    preflight_type_change!(op)
    preflight_null_tightening!(op, mapping)
  end

  defp preflight_op!(%{op: :rebuild_enum_type} = op, actual, _mapping) do
    removed_values = actual.enum_types[op.enum_type] -- op.values

    if removed_values != [] do
      Enum.each(op.columns, fn {table, column} ->
        preflight_removed_enum_values!(table, column, removed_values)
      end)
    end
  end

  defp preflight_op!(_op, _actual, _mapping), do: :ok

  defp preflight_removed_enum_values!(table, column, removed_values) do
    count = count_result(DDL.enum_values_check_statement(table, column, removed_values))

    if count > 0 do
      values = Enum.map_join(removed_values, ", ", &"'#{&1}'")

      raise ~s(found #{count} #{pluralize_rows(count)} in "#{table}"."#{column}" ) <>
              "holding removed enum #{pluralize_values(removed_values)} #{values} - " <>
              "update the rows or re-add the #{pluralize_values(removed_values)}"
    end
  end

  defp preflight_type_change!(op) do
    if op.before.type != op.after.type do
      case DDL.cast_class(op.before.type, op.after.type) do
        :safe ->
          :ok

        :data_dependent ->
          preflight_cast_rows!(op)

        :unsupported ->
          raise ~s(changing column "#{op.column}" on table "#{op.table}" ) <>
                  "from #{op.before.type} to #{op.after.type} is not supported - " <>
                  "remove the attribute and re-add it with the new type"
      end
    end
  end

  defp raise_alien!(description) do
    raise "unknown #{description} in the hologram_data schema - " <>
            "this schema is model-managed - " <>
            "move the object to another schema or remove it"
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
