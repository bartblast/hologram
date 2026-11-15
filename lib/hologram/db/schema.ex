defmodule Hologram.DB.Schema do
  @moduledoc false

  # Stand-in for the actual side of tables that exist only in the target - every
  # target foreign key and index then diffs as an add.
  @absent_table %{columns: %{}, primary_key: nil, foreign_keys: %{}, indexes: %{}}

  # Apply phases: the renames the pairing pass finds first, so every later op can name
  # objects by their target names; then destructive ops in reverse dependency order, and
  # constructive ops after in dependency order. Enum value adds and rebuilds share one phase -
  # a given type emits either, never both.
  @phases %{
    rename_table: 0,
    rename_enum_type: 0,
    rename_index: 0,
    drop_foreign_key: 1,
    drop_index: 2,
    drop_column: 3,
    drop_table: 4,
    drop_enum_type: 5,
    create_enum_type: 6,
    add_enum_value: 7,
    rebuild_enum_type: 7,
    create_table: 8,
    add_column: 9,
    alter_column: 10,
    rename_constraint: 11,
    add_foreign_key: 12,
    create_index: 13
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
  (:create_table carries neither) - dropped tables emit their :drop_foreign_key ops, and
  nothing else (their columns and indexes die with them, and block nothing meanwhile,
  but a foreign key outlives its table long enough to refuse the drop of the table it
  references, which another drop in the same diff may be). Raises ArgumentError when
  primary key columns mismatch - no derivable schema can produce that, so it means a
  hand-edited database.

  Enum types are identified by name: target-only emit :create_enum_type (with values),
  actual-only emit :drop_enum_type. When a shared type's values changed and the actual
  values survive in order (pure additions), each new value emits :add_enum_value with a
  :position ({:before, value} anchored on the nearest following pre-existing value, nil
  to append at the tail) - anything else (removal, reorder) emits :rebuild_enum_type
  carrying the new values and the columns using the type. A name-keyed diff cannot
  detect value renames - they surface as rebuilds.

  With renames: true, the default, a pairing pass runs first and recognises an object
  whose name changed while its definition didn't. A join table only in the actual term
  pairs with one only in the target when both are join-shaped over the same two tables
  and no other unpaired join table on either side has those ends - it emits :rename_table
  (with :from and :to), and its constraints and reverse index then diff as a shared
  table's. An entity table never pairs. An enum type only in the actual term pairs with
  one only in the target through a column both sides share that has the one type in the
  actual term and the other in the target, one to one - it emits :rename_enum_type (with
  :from and :to), and its values then diff under the new name. An index on a table both
  sides share pairs with one of the target's when both are unmatched by name, their
  definitions are equal, no other unmatched index on either side of that table has the
  same definition, and no actual index or primary key holds the target name - it emits
  :rename_index (with :table, :from and :to). The rest of the diff runs against the
  actual term as the renames leave it. renames: false skips the pass: a migration states
  its renames in model ops, so its renderer pairs nothing by definition.

  The op list is ordered by apply phase - the renames first (tables, then enum types,
  then indexes), then destructive kinds in reverse dependency order, constructive kinds
  after in dependency order (drop_foreign_key, drop_index, drop_column, drop_table,
  drop_enum_type, create_enum_type, enum value changes, create_table, add_column,
  alter_column, rename_constraint, add_foreign_key, create_index) - and alphabetically
  by table and name within each phase, so the same terms always produce the same op
  sequence.
  """
  @spec diff(%{atom => any}, %{atom => any}, keyword) :: list(%{atom => any})
  def diff(actual, target, opts \\ []) do
    {rename_ops, actual} =
      if Keyword.get(opts, :renames, true),
        do: pair_renames(actual, target),
        else: {[], actual}

    ops =
      table_ops(actual.tables, target.tables) ++
        column_ops(actual.tables, target.tables) ++
        constraint_index_ops(actual.tables, target.tables) ++
        enum_ops(actual, target)

    Enum.sort_by(rename_ops ++ ops, &@phases[&1.op])
  end

  @doc """
  Returns the physical schema term derived from the given mapping.

  The term is plain data keyed by physical names - the shape both sides of the
  reconciliation comparison share. :tables maps each table name (entity tables and
  join tables alike) to its definition: :columns (column name to %{type:, collation:,
  null:}), :primary_key (%{columns:, constraint:}), :foreign_keys (owning column name
  to %{references:, on_delete:, constraint:}), and :indexes (index name to %{columns:, nulls_distinct:, unique:}).
  :enum_types maps each derived enum type name to its values in declaration order.
  Join table columns are fixed: source_id/target_id uuid NOT NULL with a composite
  primary key, both columns FK ON DELETE RESTRICT, and the reverse index over
  (target_id, source_id). Entity table foreign keys are ON DELETE RESTRICT, except the
  role grant store's user references, which are ON DELETE NO ACTION.
  """
  @spec from_mapping(%{module => %{atom => any}}) :: %{atom => any}
  def from_mapping(mapping) do
    tables =
      mapping
      |> Enum.flat_map(fn {entity_type, entity_mapping} ->
        [
          entity_table(entity_type, entity_mapping)
          | Enum.map(entity_mapping.join_tables, &join_table/1)
        ]
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

    # A dropped table joins the foreign key drop pass and no other. Its columns and indexes
    # die with it and block nothing meanwhile, but its foreign keys outlive it long enough
    # to refuse the drop of a table they reference - which, when both tables go in one diff,
    # is another drop in this very list. Emitting them puts every constraint in phase 0,
    # ahead of every phase 3 table drop, so the alphabetical order tables are dropped in
    # stops deciding whether the diff applies.
    fk_drop_names =
      actual_tables
      |> Map.keys()
      |> Enum.concat(target_names)
      |> Enum.uniq()
      |> Enum.sort()

    kinds = [
      {&fk_drop_ops/3, fk_drop_names},
      {&index_drop_ops/3, target_names},
      {&constraint_rename_ops/3, target_names},
      {&fk_add_ops/3, target_names},
      {&index_create_ops/3, target_names}
    ]

    Enum.flat_map(kinds, fn {kind_ops, names} ->
      Enum.flat_map(names, fn table ->
        kind_ops.(
          table,
          Map.get(actual_tables, table, @absent_table),
          Map.get(target_tables, table, @absent_table)
        )
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

  # The role grant store's user references never rewrite rows: a cascade or set-null fired
  # by the database would change synced rows without an oplog event, stranding stale grants
  # on clients - deleting a user revokes their grants through the framework path instead.
  defp delete_action(Hologram.Auth.RoleGrant), do: :no_action

  defp delete_action(_entity_type), do: :restrict

  defp entity_table(entity_type, entity_mapping) do
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
           on_delete: delete_action(entity_type),
           constraint: column.fk_constraint
         }}
      end)

    column_indexes =
      entity_mapping.columns
      |> Enum.filter(& &1.index)
      |> Map.new(&{&1.index, %{columns: [&1.name], nulls_distinct: true, unique: false}})

    indexes = Map.merge(column_indexes, entity_mapping.indexes)

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
      %{
        op: :create_index,
        table: table,
        index: name,
        columns: target_index.columns,
        nulls_distinct: target_index.nulls_distinct,
        unique: target_index.unique
      }
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
       indexes: %{
         join_table.reverse_index => %{
           columns: ["target_id", "source_id"],
           nulls_distinct: true,
           unique: false
         }
       }
     }}
  end

  # A definition held by one unmatched index on each side of a table is a rename - two or more
  # on either side give no way to tell which became which, and those stay a drop plus a create.
  defp index_rename_candidates(actual_indexes, target_indexes) do
    actual_by_definition = unmatched_by_definition(actual_indexes, target_indexes)
    target_by_definition = unmatched_by_definition(target_indexes, actual_indexes)

    actual_by_definition
    |> Enum.flat_map(fn {definition, actual_names} ->
      case {actual_names, Map.get(target_by_definition, definition)} do
        {[from], [to]} -> [{from, to}]
        _unpaired -> []
      end
    end)
    |> Enum.sort()
  end

  # An enum type pairs through the columns that use it: an actual type only in the actual
  # term and a target type only in the target pair when every column both sides share by
  # table and name that has the actual type in the actual term has the target type in the
  # target, and no such column ties the target type to another actual one. A column on the
  # old type going anywhere else - text, another type - would leave the renamed type in use
  # by a column the rest of the diff then changes, which no rebuild of the type expects.
  defp pair_enum_type_renames(actual, target) do
    shared_column_types =
      for {table, actual_definition} <- actual.tables,
          %{columns: target_columns} <- [target.tables[table]],
          {column, %{type: from}} <- actual_definition.columns,
          %{type: to} <- [target_columns[column]],
          Map.has_key?(actual.enum_types, from) and not Map.has_key?(target.enum_types, from),
          uniq: true,
          do: {from, to}

    targets_by_from = Enum.group_by(shared_column_types, &elem(&1, 0), &elem(&1, 1))
    froms_by_to = Enum.group_by(shared_column_types, &elem(&1, 1), &elem(&1, 0))

    ops =
      shared_column_types
      |> Enum.filter(fn {from, to} ->
        Map.has_key?(target.enum_types, to) and not Map.has_key?(actual.enum_types, to) and
          targets_by_from[from] == [to] and froms_by_to[to] == [from]
      end)
      |> Enum.sort()
      |> Enum.map(fn {from, to} -> %{op: :rename_enum_type, from: from, to: to} end)

    renamed_types = Map.new(ops, &{&1.from, &1.to})

    enum_types =
      Map.new(actual.enum_types, fn {name, values} ->
        {Map.get(renamed_types, name, name), values}
      end)

    tables =
      Map.new(actual.tables, fn {table, definition} ->
        columns =
          Map.new(definition.columns, fn {column, column_definition} ->
            type = Map.get(renamed_types, column_definition.type, column_definition.type)
            {column, %{column_definition | type: type}}
          end)

        {table, %{definition | columns: columns}}
      end)

    {ops, %{actual | enum_types: enum_types, tables: tables}}
  end

  # The renames run before every drop, so a rename can't take a name an actual index or primary
  # key still holds, nor one an earlier rename of this pass took - PostgreSQL would refuse it.
  # Only those two kinds are checked: a derived index name always carries its $idx or $uidx
  # kind, which no derived table name does, so a table or other relation holding it can only
  # be a hand-made one, which refuses a create_index of that name just the same.
  defp pair_index_renames(actual, target) do
    held_names =
      actual.tables
      |> Enum.flat_map(fn {_table, definition} ->
        pk_names = if definition.primary_key, do: [definition.primary_key.constraint], else: []
        Map.keys(definition.indexes) ++ pk_names
      end)
      |> MapSet.new()

    {reversed_ops, _held_names} =
      actual.tables
      |> Map.keys()
      |> Enum.filter(&Map.has_key?(target.tables, &1))
      |> Enum.sort()
      |> Enum.flat_map(fn table ->
        actual.tables[table].indexes
        |> index_rename_candidates(target.tables[table].indexes)
        |> Enum.map(fn {from, to} -> %{op: :rename_index, table: table, from: from, to: to} end)
      end)
      |> Enum.reduce({[], held_names}, fn op, {ops, held_names} ->
        if MapSet.member?(held_names, op.to),
          do: {ops, held_names},
          else: {[op | ops], MapSet.put(held_names, op.to)}
      end)

    ops = Enum.reverse(reversed_ops)

    tables =
      Enum.reduce(ops, actual.tables, fn op, tables ->
        update_in(tables, [op.table, :indexes], fn indexes ->
          {definition, indexes} = Map.pop!(indexes, op.from)
          Map.put(indexes, op.to, definition)
        end)
      end)

    {ops, %{actual | tables: tables}}
  end

  # A join table pairs by its two ends: an actual table and a target table, each only on its
  # side, both join-shaped and over the same two tables, with no other unpaired join table over
  # those ends on either side - two relationships between the same two tables give no way to
  # tell which became which. Entity tables never pair: nothing in a table's definition tells it
  # apart from another one with the same columns.
  defp pair_join_table_renames(actual, target) do
    actual_by_ends = unpaired_join_tables_by_ends(actual.tables, target.tables)
    target_by_ends = unpaired_join_tables_by_ends(target.tables, actual.tables)

    ops =
      actual_by_ends
      |> Enum.flat_map(fn {ends, actual_names} ->
        case {actual_names, Map.get(target_by_ends, ends)} do
          {[from], [to]} -> [%{op: :rename_table, from: from, to: to}]
          _unpaired -> []
        end
      end)
      |> Enum.sort_by(& &1.from)

    tables =
      Enum.reduce(ops, actual.tables, fn op, tables ->
        {definition, tables} = Map.pop!(tables, op.from)
        Map.put(tables, op.to, definition)
      end)

    {ops, %{actual | tables: tables}}
  end

  # The table renames go first, so the enum type and index pairing and the constraint passes
  # see a renamed join table as one both sides share, and rename its reverse index and
  # constraints with it. An enum type renamed through its column then diffs its values under
  # the new name, as adds or a rebuild.
  defp pair_renames(actual, target) do
    {table_ops, tables_renamed} = pair_join_table_renames(actual, target)
    {enum_type_ops, enum_types_renamed} = pair_enum_type_renames(tables_renamed, target)
    {index_ops, renamed} = pair_index_renames(enum_types_renamed, target)

    {table_ops ++ enum_type_ops ++ index_ops, renamed}
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

  # The ends of a join-shaped table, matched whole - one a hand edit left without its primary
  # key, a foreign key or one of its two columns has none, and never pairs.
  defp join_table_ends(%{
         columns: columns,
         primary_key: %{columns: ["source_id", "target_id"]},
         foreign_keys: %{
           "source_id" => %{references: source_table},
           "target_id" => %{references: target_table}
         }
       })
       when map_size(columns) == 2 and is_map_key(columns, "source_id") and
              is_map_key(columns, "target_id") do
    [{source_table, target_table}]
  end

  defp join_table_ends(_definition), do: []

  # The join-shaped tables the other side doesn't hold by name, grouped by their ends, with the
  # names sorted.
  defp unpaired_join_tables_by_ends(tables, other_tables) do
    tables
    |> Enum.reject(fn {name, _definition} -> Map.has_key?(other_tables, name) end)
    |> Enum.flat_map(fn {name, definition} ->
      definition
      |> join_table_ends()
      |> Enum.map(&{&1, name})
    end)
    |> Enum.group_by(fn {ends, _name} -> ends end, fn {_ends, name} -> name end)
    |> Map.new(fn {ends, names} -> {ends, Enum.sort(names)} end)
  end

  # Name to definition, for the indexes the other side lacks under the same name and definition,
  # grouped by definition with the names sorted.
  defp unmatched_by_definition(indexes, other_indexes) do
    indexes
    |> Enum.reject(fn {name, definition} -> other_indexes[name] == definition end)
    |> Enum.group_by(fn {_name, definition} -> definition end, fn {name, _definition} -> name end)
    |> Map.new(fn {definition, names} -> {definition, Enum.sort(names)} end)
  end

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
