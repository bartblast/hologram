defmodule Hologram.Database.Introspection do
  @moduledoc false

  alias Hologram.Database.Connection

  @data_schema "hologram_data"

  # pg_type names already match the mapper's type vocabulary except boolean.
  @typname_translations %{"bool" => "boolean"}

  # TODO: extend the term with primary keys, foreign keys, indexes, and enum types.
  @doc """
  Returns the physical schema term introspected from the database - the actual side of
  the reconciliation comparison, in the same shape as Schema.from_mapping/1 produces.

  Reads only the hologram_data schema, via pg_catalog. :tables maps each table name to
  its :columns (column name to %{type:, collation:, null:}), with types translated into
  the mapper's vocabulary and dropped-column tombstones filtered out.
  """
  @spec schema() :: %{atom => any}
  def schema do
    %{tables: tables()}
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

    Map.new(table_names(), fn name ->
      {name, %{columns: Map.get(columns_by_table, name, %{})}}
    end)
  end
end
