defmodule Hologram.DB.Introspection do
  @moduledoc false

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper

  # pg_constraint.confdeltype decoding.
  @delete_actions %{
    "a" => :no_action,
    "c" => :cascade,
    "d" => :set_default,
    "n" => :set_null,
    "r" => :restrict
  }

  # The ways an index can differ from the plain btree over whole columns, with default sort
  # order, operator classes and collations, that every derived index is - sorted, and in the
  # order the index query reads their flags.
  @non_plain_reasons [
    :collation,
    :constraint,
    :expression,
    :include,
    :method,
    :operator_class,
    :predicate,
    :sort_order
  ]

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
  %{columns:, nulls_distinct:, unique:} in index column order, primary-key-backing
  indexes excluded - they are implied by the constraint). An index that isn't a plain
  btree over whole columns with default options - a predicate, an expression, INCLUDE
  columns, another access method, a non-default sort order, operator class or collation,
  or an owning constraint - also carries :non_plain, the sorted list of those reasons
  (:collation, :constraint, :expression, :include, :method, :operator_class, :predicate,
  :sort_order), so its definition equals no derived one. :enum_types maps each enum
  type name to its values in enum sort order - a type declared with no values yet
  maps to an empty list.

  Reading the null-distinctness of indexes requires PostgreSQL 15 or newer - the
  framework's documented floor.
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

    {:ok, %{rows: rows}} = Connection.query(statement, [Mapper.data_schema()])

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

    {:ok, %{rows: rows}} = Connection.query(statement, [Mapper.data_schema()])

    Enum.reduce(rows, {%{}, %{}}, &constraint_entry/2)
  end

  # Driven by pg_type rather than pg_enum: a type declared with no values yet has no
  # pg_enum rows at all, so a query starting from the labels never lists it - the
  # reconciler then re-created it on every boot and the drift check reported it missing
  # while it stood. The role grant store's role type is exactly that for as long as the
  # app has a user entity and no role.
  defp enum_types do
    statement = """
    SELECT t.typname, e.enumlabel
    FROM pg_catalog.pg_type t
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    LEFT JOIN pg_catalog.pg_enum e ON e.enumtypid = t.oid
    WHERE n.nspname = $1 AND t.typtype = 'e'
    ORDER BY t.typname, e.enumsortorder
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [Mapper.data_schema()])

    rows
    |> Enum.group_by(fn [typname, _label] -> typname end)
    |> Map.new(fn {typname, type_rows} ->
      {typname, for([_typname, label] <- type_rows, label != nil, do: label)}
    end)
  end

  defp index_entry([_table, index, columns, nulls_distinct, unique | reason_flags]) do
    non_plain =
      @non_plain_reasons
      |> Enum.zip(reason_flags)
      |> Enum.filter(fn {_reason, flag} -> flag end)
      |> Enum.map(fn {reason, _flag} -> reason end)

    definition = %{columns: columns, nulls_distinct: nulls_distinct, unique: unique}

    if non_plain == [],
      do: {index, definition},
      else: {index, Map.put(definition, :non_plain, non_plain)}
  end

  # Each reason flag is one way an index differs from the plain btree over whole columns the
  # mapper derives. The column list alone can't tell: it reads only the key columns indkey
  # names, so an expression entry is dropped and an INCLUDE column counted as a key. The
  # order of the flags is @non_plain_reasons'. A foreign key also names the index it is
  # checked against in conindid - on its own table too, when it references that table - so
  # only a unique or exclusion constraint counts as owning one.
  defp indexes do
    statement = """
    SELECT c.relname,
           ic.relname,
           (SELECT array_agg(a.attname ORDER BY k.ord)
            FROM unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
            JOIN pg_catalog.pg_attribute a
              ON a.attrelid = i.indrelid AND a.attnum = k.attnum),
           NOT i.indnullsnotdistinct,
           i.indisunique,
           EXISTS (SELECT 1
                   FROM unnest(i.indcollation::oid[], i.indkey::int2[]) AS k(collation_oid, attnum)
                   JOIN pg_catalog.pg_attribute a
                     ON a.attrelid = i.indrelid AND a.attnum = k.attnum
                   WHERE k.collation_oid <> a.attcollation),
           EXISTS (SELECT 1
                   FROM pg_catalog.pg_constraint con
                   WHERE con.conindid = i.indexrelid AND con.conrelid = i.indrelid
                     AND con.contype <> 'f'),
           i.indexprs IS NOT NULL,
           i.indnkeyatts <> i.indnatts,
           am.amname <> 'btree',
           EXISTS (SELECT 1
                   FROM unnest(i.indclass::oid[]) AS k(opclass_oid)
                   JOIN pg_catalog.pg_opclass oc ON oc.oid = k.opclass_oid
                   WHERE NOT oc.opcdefault),
           i.indpred IS NOT NULL,
           EXISTS (SELECT 1 FROM unnest(i.indoption::int2[]) AS k(sort_option) WHERE k.sort_option <> 0)
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i.indexrelid
    JOIN pg_catalog.pg_am am ON am.oid = ic.relam
    JOIN pg_catalog.pg_class c ON c.oid = i.indrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND NOT i.indisprimary
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [Mapper.data_schema()])

    rows
    |> Enum.group_by(fn [table | _rest] -> table end)
    |> Map.new(fn {table, table_rows} -> {table, Map.new(table_rows, &index_entry/1)} end)
  end

  defp table_names do
    statement = """
    SELECT c.relname
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relkind = 'r'
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [Mapper.data_schema()])

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
