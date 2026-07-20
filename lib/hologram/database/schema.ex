defmodule Hologram.Database.Schema do
  @moduledoc false

  # Stand-in for the actual side of tables that exist only in the target - every
  # target foreign key and index then diffs as an add.
  @absent_table %{columns: %{}, primary_key: nil, foreign_keys: %{}, indexes: %{}}

  # Apply phases: destructive ops first in reverse dependency order, constructive ops
  # after in dependency order. Enum value adds and rebuilds share one phase - a given
  # type emits either, never both.
  @phases %{
    drop_foreign_key: 0,
    drop_index: 1,
    drop_column: 2,
    drop_table: 3,
    drop_enum_type: 4,
    create_enum_type: 5,
    add_enum_value: 6,
    rebuild_enum_type: 6,
    create_table: 7,
    add_column: 8,
    alter_column: 9,
    rename_constraint: 10,
    add_foreign_key: 11,
    create_index: 12
  }

  @doc """
  Returns the physical change ops that converge the actual schema term to the target
  schema term.

  Each op is a self-contained map with an :op kind and the term fragments needed to
  render it. Tables present only in the target emit :create_table (columns and primary
  key - foreign keys and indexes are always separate ops), tables present only in the
  actual schema emit :drop_table (their own constraints, indexes, and columns die with
  them). Tables present on both sides diff column by column: target-only columns emit
  :add_column (with the column definition), actual-only columns emit :drop_column, and
  columns whose definitions differ emit :alter_column with :before/:after payloads.

  Foreign keys diff by owning column: target-only emit :add_foreign_key, actual-only
  emit :drop_foreign_key, a structural change (referenced table or delete action) emits
  drop plus add, and a constraint-name-only mismatch emits :rename_constraint - the
  same op a primary key constraint name mismatch emits. Indexes are identified by name:
  target-only emit :create_index, actual-only emit :drop_index, and a definition change
  emits drop plus create. New tables emit adds for their foreign keys and indexes
  (:create_table carries neither) - dropped tables emit no constraint or index drops
  (they die with the table). Raises ArgumentError when primary key columns mismatch -
  no derivable schema can produce that, so it means a hand-edited database.

  Enum types are identified by name: target-only emit :create_enum_type (with values),
  actual-only emit :drop_enum_type. When a shared type's values changed and the actual
  values survive in order (pure additions), each new value emits :add_enum_value with a
  :position ({:before, value} anchored on the nearest following pre-existing value, nil
  to append at the tail) - anything else (removal, reorder) emits :rebuild_enum_type
  carrying the new values and the columns using the type. A name-keyed diff cannot
  detect value renames - they surface as rebuilds.

  The op list is ordered by apply phase - destructive kinds first in reverse dependency
  order, constructive kinds after in dependency order (drop_foreign_key, drop_index,
  drop_column, drop_table, drop_enum_type, create_enum_type, enum value changes,
  create_table, add_column, alter_column, rename_constraint, add_foreign_key,
  create_index) - and alphabetically by table and name within each phase, so the same
  terms always produce the same op sequence.
  """
  @spec diff(%{atom => any}, %{atom => any}) :: list(%{atom => any})
  def diff(actual, target) do
    ops =
      table_ops(actual.tables, target.tables) ++
        column_ops(actual.tables, target.tables) ++
        constraint_index_ops(actual.tables, target.tables) ++
        enum_ops(actual, target)

    Enum.sort_by(ops, &@phases[&1.op])
  end

  @doc """
  Returns the physical schema term derived from the given mapping.

  The term is plain data keyed by physical names - the shape both sides of the
  reconciliation comparison share. :tables maps each table name (entity tables and
  join tables alike) to its definition: :columns (column name to %{type:, collation:,
  null:}), :primary_key (%{columns:, constraint:}), :foreign_keys (owning column name
  to %{references:, on_delete:, constraint:}), and :indexes (index name to %{columns:}).
  :enum_types maps each derived enum type name to its values in declaration order.
  Join table columns are fixed: source_id/target_id uuid NOT NULL with a composite
  primary key, both columns FK ON DELETE RESTRICT, and the reverse index over
  (target_id, source_id).
  """
  @spec from_mapping(%{module => %{atom => any}}) :: %{atom => any}
  def from_mapping(mapping) do
    tables =
      mapping
      |> Enum.flat_map(fn {_entity_type, entity_mapping} ->
        [entity_table(entity_mapping) | Enum.map(entity_mapping.join_tables, &join_table/1)]
      end)
      |> Map.new()

    enum_types =
      mapping
      |> Enum.flat_map(fn {_entity_type, entity_mapping} ->
        entity_mapping.columns
        |> Enum.filter(& &1.enum_values)
        |> Enum.map(&{&1.sql_type, &1.enum_values})
      end)
      |> Map.new()

    %{tables: tables, enum_types: enum_types}
  end

  defp column_add_ops(table, actual_columns, target_columns) do
    target_columns
    |> Enum.reject(fn {name, _definition} -> Map.has_key?(actual_columns, name) end)
    |> Enum.sort_by(fn {name, _definition} -> name end)
    |> Enum.map(fn {name, definition} ->
      %{op: :add_column, table: table, column: name, definition: definition}
    end)
  end

  defp column_alter_ops(table, actual_columns, target_columns) do
    actual_columns
    |> Enum.sort_by(fn {name, _definition} -> name end)
    |> Enum.flat_map(fn {name, actual_definition} ->
      case target_columns[name] do
        nil ->
          []

        ^actual_definition ->
          []

        target_definition ->
          [
            %{
              op: :alter_column,
              table: table,
              column: name,
              before: actual_definition,
              after: target_definition
            }
          ]
      end
    end)
  end

  defp column_drop_ops(table, actual_columns, target_columns) do
    actual_columns
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(target_columns, &1))
    |> Enum.sort()
    |> Enum.map(&%{op: :drop_column, table: table, column: &1})
  end

  defp column_ops(actual_tables, target_tables) do
    shared_tables =
      actual_tables
      |> Map.keys()
      |> Enum.filter(&Map.has_key?(target_tables, &1))
      |> Enum.sort()

    ops_per_kind =
      Enum.map([&column_drop_ops/3, &column_add_ops/3, &column_alter_ops/3], fn kind_ops ->
        Enum.flat_map(shared_tables, fn table ->
          kind_ops.(table, actual_tables[table].columns, target_tables[table].columns)
        end)
      end)

    Enum.concat(ops_per_kind)
  end

  defp constraint_index_ops(actual_tables, target_tables) do
    target_names =
      target_tables
      |> Map.keys()
      |> Enum.sort()

    kinds = [
      &fk_drop_ops/3,
      &index_drop_ops/3,
      &constraint_rename_ops/3,
      &fk_add_ops/3,
      &index_create_ops/3
    ]

    Enum.flat_map(kinds, fn kind_ops ->
      Enum.flat_map(target_names, fn table ->
        kind_ops.(table, Map.get(actual_tables, table, @absent_table), target_tables[table])
      end)
    end)
  end

  defp constraint_rename_ops(table, actual_definition, target_definition) do
    fk_renames =
      actual_definition.foreign_keys
      |> Enum.sort_by(fn {column, _fk} -> column end)
      |> Enum.flat_map(fn {column, actual_fk} ->
        target_fk = target_definition.foreign_keys[column]

        if target_fk && fk_structure(target_fk) == fk_structure(actual_fk) &&
             target_fk.constraint != actual_fk.constraint do
          [
            %{
              op: :rename_constraint,
              table: table,
              from: actual_fk.constraint,
              to: target_fk.constraint
            }
          ]
        else
          []
        end
      end)

    pk_renames =
      pk_rename_ops(table, actual_definition.primary_key, target_definition.primary_key)

    pk_renames ++ fk_renames
  end

  defp entity_table(entity_mapping) do
    columns =
      Map.new(entity_mapping.columns, fn column ->
        {column.name, %{type: column.sql_type, collation: column.collation, null: column.null}}
      end)

    reference_columns = Enum.filter(entity_mapping.columns, & &1.references)

    foreign_keys =
      Map.new(reference_columns, fn column ->
        {column.name,
         %{
           references: column.references,
           on_delete: :restrict,
           constraint: column.fk_constraint
         }}
      end)

    indexes = Map.new(reference_columns, &{&1.fk_index, %{columns: [&1.name]}})

    {entity_mapping.table,
     %{
       columns: columns,
       primary_key: %{columns: ["id"], constraint: entity_mapping.pk_constraint},
       foreign_keys: foreign_keys,
       indexes: indexes
     }}
  end

  defp enum_ops(actual, target) do
    drops =
      actual.enum_types
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(target.enum_types, &1))
      |> Enum.sort()
      |> Enum.map(&%{op: :drop_enum_type, enum_type: &1})

    creates =
      target.enum_types
      |> Enum.reject(fn {name, _values} -> Map.has_key?(actual.enum_types, name) end)
      |> Enum.sort_by(fn {name, _values} -> name end)
      |> Enum.map(fn {name, values} ->
        %{op: :create_enum_type, enum_type: name, values: values}
      end)

    changes =
      target.enum_types
      |> Enum.sort_by(fn {name, _values} -> name end)
      |> Enum.flat_map(fn {name, target_values} ->
        enum_value_ops(name, actual.enum_types[name], target_values, target.tables)
      end)

    drops ++ creates ++ changes
  end

  defp enum_type_columns(name, tables) do
    tables
    |> Enum.sort_by(fn {table, _definition} -> table end)
    |> Enum.flat_map(fn {table, definition} ->
      definition.columns
      |> Enum.filter(fn {_column, column_definition} -> column_definition.type == name end)
      |> Enum.sort_by(fn {column, _definition} -> column end)
      |> Enum.map(fn {column, _definition} -> {table, column} end)
    end)
  end

  defp enum_value_add_ops(name, actual_values, target_values) do
    target_values
    |> Enum.with_index()
    |> Enum.reject(fn {value, _index} -> value in actual_values end)
    |> Enum.map(fn {value, index} ->
      following_actual_value =
        target_values
        |> Enum.drop(index + 1)
        |> Enum.find(&(&1 in actual_values))

      position = if following_actual_value, do: {:before, following_actual_value}

      %{op: :add_enum_value, enum_type: name, value: value, position: position}
    end)
  end

  defp enum_value_ops(_name, nil, _target_values, _target_tables), do: []

  defp enum_value_ops(_name, actual_values, actual_values, _target_tables), do: []

  defp enum_value_ops(name, actual_values, target_values, target_tables) do
    if subsequence?(actual_values, target_values) do
      enum_value_add_ops(name, actual_values, target_values)
    else
      [
        %{
          op: :rebuild_enum_type,
          enum_type: name,
          values: target_values,
          columns: enum_type_columns(name, target_tables)
        }
      ]
    end
  end

  defp fk_add_ops(table, actual_definition, target_definition) do
    target_definition.foreign_keys
    |> Enum.sort_by(fn {column, _fk} -> column end)
    |> Enum.reject(fn {column, target_fk} ->
      case actual_definition.foreign_keys[column] do
        nil -> false
        actual_fk -> fk_structure(actual_fk) == fk_structure(target_fk)
      end
    end)
    |> Enum.map(fn {column, target_fk} ->
      %{
        op: :add_foreign_key,
        table: table,
        column: column,
        references: target_fk.references,
        on_delete: target_fk.on_delete,
        constraint: target_fk.constraint
      }
    end)
  end

  defp fk_drop_ops(table, actual_definition, target_definition) do
    actual_definition.foreign_keys
    |> Enum.sort_by(fn {column, _fk} -> column end)
    |> Enum.reject(fn {column, actual_fk} ->
      case target_definition.foreign_keys[column] do
        nil -> false
        target_fk -> fk_structure(actual_fk) == fk_structure(target_fk)
      end
    end)
    |> Enum.map(fn {_column, actual_fk} ->
      %{op: :drop_foreign_key, table: table, constraint: actual_fk.constraint}
    end)
  end

  defp fk_structure(fk), do: Map.take(fk, [:on_delete, :references])

  defp index_create_ops(table, actual_definition, target_definition) do
    target_definition.indexes
    |> Enum.sort_by(fn {name, _index} -> name end)
    |> Enum.reject(fn {name, target_index} ->
      actual_definition.indexes[name] == target_index
    end)
    |> Enum.map(fn {name, target_index} ->
      %{op: :create_index, table: table, index: name, columns: target_index.columns}
    end)
  end

  defp index_drop_ops(_table, actual_definition, target_definition) do
    actual_definition.indexes
    |> Enum.sort_by(fn {name, _index} -> name end)
    |> Enum.reject(fn {name, actual_index} ->
      target_definition.indexes[name] == actual_index
    end)
    |> Enum.map(fn {name, _index} -> %{op: :drop_index, index: name} end)
  end

  defp join_table(join_table) do
    columns = %{
      "source_id" => %{type: "uuid", collation: nil, null: false},
      "target_id" => %{type: "uuid", collation: nil, null: false}
    }

    foreign_keys = %{
      "source_id" => %{
        references: join_table.source_table,
        on_delete: :restrict,
        constraint: join_table.source_fk_constraint
      },
      "target_id" => %{
        references: join_table.target_table,
        on_delete: :restrict,
        constraint: join_table.target_fk_constraint
      }
    }

    {join_table.name,
     %{
       columns: columns,
       primary_key: %{
         columns: ["source_id", "target_id"],
         constraint: join_table.pk_constraint
       },
       foreign_keys: foreign_keys,
       indexes: %{join_table.reverse_index => %{columns: ["target_id", "source_id"]}}
     }}
  end

  defp pk_rename_ops(_table, nil, _target_pk), do: []

  defp pk_rename_ops(table, actual_pk, target_pk) do
    cond do
      actual_pk.columns != target_pk.columns ->
        raise ArgumentError,
              "primary key columns mismatch on table \"#{table}\" " <>
                "(actual: #{inspect(actual_pk.columns)}, target: #{inspect(target_pk.columns)}) - " <>
                "no derivable schema can produce this, the database was edited by hand"

      actual_pk.constraint != target_pk.constraint ->
        [
          %{
            op: :rename_constraint,
            table: table,
            from: actual_pk.constraint,
            to: target_pk.constraint
          }
        ]

      true ->
        []
    end
  end

  defp subsequence?([], _list), do: true

  defp subsequence?(_values, []), do: false

  defp subsequence?([head | tail], [head | list_tail]), do: subsequence?(tail, list_tail)

  defp subsequence?(values, [_head | list_tail]), do: subsequence?(values, list_tail)

  defp table_ops(actual_tables, target_tables) do
    drops =
      actual_tables
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(target_tables, &1))
      |> Enum.sort()
      |> Enum.map(&%{op: :drop_table, table: &1})

    creates =
      target_tables
      |> Enum.reject(fn {name, _definition} -> Map.has_key?(actual_tables, name) end)
      |> Enum.sort_by(fn {name, _definition} -> name end)
      |> Enum.map(fn {name, definition} ->
        %{
          op: :create_table,
          table: name,
          columns: definition.columns,
          primary_key: definition.primary_key
        }
      end)

    drops ++ creates
  end
end
