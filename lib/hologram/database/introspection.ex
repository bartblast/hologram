defmodule Hologram.Database.Introspection do
  @moduledoc false

  alias Hologram.Database.Connection

  @data_schema "hologram_data"

  # pg_constraint.confdeltype decoding.
  @delete_actions %{
    "a" => :no_action,
    "c" => :cascade,
    "d" => :set_default,
    "n" => :set_null,
    "r" => :restrict
  }

  # pg_type names already match the mapper's type vocabulary except boolean.
  @typname_translations %{"bool" => "boolean"}

  @doc """
  Returns the physical schema term introspected from the database - the actual side of
  the reconciliation comparison, in the same shape as Schema.from_mapping/1 produces.

  Reads only the hologram_data schema, via pg_catalog. :tables maps each table name to
  its :columns (column name to %{type:, collation:, null:}, with types translated into
  the mapper's vocabulary and dropped-column tombstones filtered out), :primary_key
  (%{columns:, constraint:}, nil when the table has none), :foreign_keys (owning column
  name to %{references:, on_delete:, constraint:}), and :indexes (index name to
  %{columns:} in index column order, primary-key-backing indexes excluded - they are
  implied by the constraint). :enum_types maps each enum type name to its values in
  enum sort order.
  """
  @spec schema() :: %{atom => any}
  def schema do
    %{tables: tables(), enum_types: enum_types()}
  end

  defp column_definitions do
    statement = """
    SELECT c.relname, a.attname, t.typname, col.collname, a.attnotnull
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_catalog.pg_type t ON t.oid = a.atttypid
    LEFT JOIN pg_catalog.pg_collation col ON col.oid = a.attcollation
    WHERE n.nspname = $1 AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [@data_schema])

    rows
    |> Enum.group_by(fn [table | _rest] -> table end)
    |> Map.new(fn {table, table_rows} -> {table, Map.new(table_rows, &column_entry/1)} end)
  end

  defp column_entry([_table, column, typname, collname, notnull]) do
    definition = %{
      type: Map.get(@typname_translations, typname, typname),
      collation: collname,
      null: not notnull
    }

    {column, definition}
  end

  defp constraint_entry([table, conname, "p", _deltype, _foreign_table, columns], {pks, fks}) do
    {Map.put(pks, table, %{columns: columns, constraint: conname}), fks}
  end

  defp constraint_entry([table, conname, "f", deltype, foreign_table, [column | _rest]], acc) do
    {pks, fks} = acc

    fk = %{
      references: foreign_table,
      on_delete: Map.fetch!(@delete_actions, deltype),
      constraint: conname
    }

    {pks, Map.update(fks, table, %{column => fk}, &Map.put(&1, column, fk))}
  end

  defp constraints do
    statement = """
    SELECT c.relname,
           con.conname,
           con.contype,
           con.confdeltype,
           ft.relname,
           (SELECT array_agg(a.attname ORDER BY k.ord)
            FROM unnest(con.conkey) WITH ORDINALITY AS k(attnum, ord)
            JOIN pg_catalog.pg_attribute a
              ON a.attrelid = con.conrelid AND a.attnum = k.attnum)
    FROM pg_catalog.pg_constraint con
    JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_catalog.pg_class ft ON ft.oid = con.confrelid
    WHERE n.nspname = $1 AND con.contype IN ('p', 'f')
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [@data_schema])

    Enum.reduce(rows, {%{}, %{}}, &constraint_entry/2)
  end

  defp enum_types do
    statement = """
    SELECT t.typname, e.enumlabel
    FROM pg_catalog.pg_enum e
    JOIN pg_catalog.pg_type t ON t.oid = e.enumtypid
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = $1
    ORDER BY t.typname, e.enumsortorder
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [@data_schema])

    rows
    |> Enum.group_by(fn [typname, _label] -> typname end)
    |> Map.new(fn {typname, type_rows} ->
      {typname, Enum.map(type_rows, fn [_typname, label] -> label end)}
    end)
  end

  defp indexes do
    statement = """
    SELECT c.relname,
           ic.relname,
           (SELECT array_agg(a.attname ORDER BY k.ord)
            FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
            JOIN pg_catalog.pg_attribute a
              ON a.attrelid = i.indrelid AND a.attnum = k.attnum)
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i.indexrelid
    JOIN pg_catalog.pg_class c ON c.oid = i.indrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND NOT i.indisprimary
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [@data_schema])

    rows
    |> Enum.group_by(fn [table | _rest] -> table end)
    |> Map.new(fn {table, table_rows} ->
      {table,
       Map.new(table_rows, fn [_table, index, columns] -> {index, %{columns: columns}} end)}
    end)
  end

  defp table_names do
    statement = """
    SELECT c.relname
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relkind = 'r'
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [@data_schema])

    Enum.map(rows, fn [name] -> name end)
  end

  defp tables do
    columns_by_table = column_definitions()
    {pks_by_table, fks_by_table} = constraints()
    indexes_by_table = indexes()

    Map.new(table_names(), fn name ->
      {name,
       %{
         columns: Map.get(columns_by_table, name, %{}),
         primary_key: Map.get(pks_by_table, name),
         foreign_keys: Map.get(fks_by_table, name, %{}),
         indexes: Map.get(indexes_by_table, name, %{})
       }}
    end)
  end
end
