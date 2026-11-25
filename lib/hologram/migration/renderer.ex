defmodule Hologram.Migration.Renderer do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.DB.Preflight
  alias Hologram.DB.QueryCompiler
  alias Hologram.DB.Schema
  alias Hologram.Entity.Model
  alias Hologram.Migration.Value
  alias Hologram.Migration.Value.Check
  alias Hologram.Migration.Value.SQL

  # The ops that take an object away - a widening keeps them until its data has moved.
  @drop_ops [:drop_column, :drop_foreign_key, :drop_index]

  # A name-keyed diff cannot express a rename - it sees a name gone and a name new - so
  # these ops render by pairing the names the mapper derives before and after them.
  @rename_ops [
    :rename_attribute,
    :rename_entity,
    :rename_enum_value,
    :rename_relationship,
    :rename_role
  ]

  @doc """
  Returns the physical ops applying the given logical ops to a database holding the
  given model, plus the model they leave behind.

  The ops are split by how they execute: :transactional runs inside the migration file's
  transaction, :tail after it commits - index builds on tables that already carry rows
  go concurrently, which PostgreSQL forbids inside a transaction. :added_columns names
  each column the transactional ops add, as the file leaves it, for the companion fill
  that runs after them.

  A required column added without a backfill carries its declared default as one, and a
  column turning required carries it as its :fill, so what the rows that predate it
  receive is settled where the op sits rather than looked up after the file's later ops
  have renamed it. The ops render in chunks, a rename starting a chunk of its own, and the
  default is the one the op's chunk leaves: a default declared or changed in the same
  chunk counts, one declared after a later rename fills nothing - the column is required,
  and refused over rows, before it arrives.

  An add with a computed backfill is a chunk of its own, so it reads the rows as the ops above
  it leave them and no op beside it can change what it fills. An entity type deleted and created
  again starts one too. A member deleted with another added under the same stored name stays in
  its chunk, in either order, and renders as a drop and an add: read as one unchanged column, the
  rows would keep the old values.

  The ops render through the mapping: the model before and after them project to physical
  schema terms, and their difference is what the database must do. Physical names
  therefore never enter the migration history - a change to the derived-name rules
  changes what the same history renders to. Rendering the ops together rather than one by
  one keeps the statements minimal: an entity arriving with its attributes is one CREATE
  TABLE, not a table followed by a column at a time.
  """
  @spec render(list(%{atom => any}), %{atom => any}) :: %{atom => any}
  def render(logical_ops, pre_model) do
    # The file is checked whole here, once: whether a required attribute's entity type was
    # created before it reads the whole file, and a chunk folded below cannot see the ones
    # before it, so the chunks skip that check. They keep the others, which hold per chunk.
    _validated_model = Model.fold(pre_model, logical_ops)

    # Judged here rather than in the fold, which every boot runs over the applied history: a rule
    # that tightens in a later release must not stop a database that already applied the file.
    Check.validate_ops!(logical_ops, pre_model)

    chunks =
      logical_ops
      |> Check.put_byte_bounds(pre_model)
      |> chunks()

    {physical_ops, post_model} = render_chunks(chunks, pre_model)

    Check.validate_enum_uses!(physical_ops, cut?(chunks))

    physical_ops
    |> walk_ops()
    |> Map.put(:post_model, post_model)
  end

  # A backfill rides its logical op, never the model - the physical column it fills is
  # found by the name the mapper derives for that attribute.
  defp attach_backfills(physical_ops, logical_ops, next_model, next_mapping) do
    backfills =
      for {op, index} <- Enum.with_index(logical_ops),
          {:ok, value} <- [Value.fetch_backfill(op)],
          not deleted_later?(op, Enum.drop(logical_ops, index + 1)),
          %{} = entry <- [next_mapping[op.entity]],
          %{} = column <- [member_column(entry, op)],
          into: %{} do
        type = filled_type(op, next_model)
        normalized = Value.normalize_constant(value, type)

        {{entry.table, column.name},
         {Codec.encode(normalized, type), fill_target(op, next_model)}}
      end

    Enum.map(physical_ops, &put_backfill(&1, backfills))
  end

  # Each chunk with the op that cut it from the one before, nil when only the kind of op changed.
  defp chunks(logical_ops) do
    logical_ops
    |> Enum.reduce([], &place_op/2)
    |> Enum.reverse()
    |> Enum.map(fn {cut, reversed_ops} -> {cut, Enum.reverse(reversed_ops)} end)
  end

  # Clears what the given columns hold from the term a diff starts at: their foreign keys, the
  # indexes over them and the enum types they alone use.
  defp clear_columns(term, table, columns) do
    names = Enum.map(columns, & &1.name)
    enum_types = for %{enum_values: values, sql_type: type} <- columns, values, do: type

    cleared_table =
      term.tables
      |> Map.fetch!(table)
      |> Map.update!(:columns, &Map.drop(&1, names))
      |> Map.update!(:foreign_keys, &Map.drop(&1, names))
      |> Map.update!(:indexes, fn indexes ->
        Map.reject(indexes, fn {_name, index} -> Enum.any?(index.columns, &(&1 in names)) end)
      end)

    %{
      term
      | enum_types: Map.drop(term.enum_types, enum_types),
        tables: Map.put(term.tables, table, cleared_table)
    }
  end

  defp clear_member(term, _op, nil, _next_entry, _next_join_tables), do: term

  defp clear_member(term, %{op: :delete_entity}, pre_entry, _next_entry, next_join_tables) do
    %{term | tables: Map.drop(term.tables, kept_join_tables(pre_entry, next_join_tables))}
  end

  defp clear_member(term, %{name: name} = op, pre_entry, next_entry, next_join_tables) do
    next_columns =
      next_entry
      |> then(&if(&1, do: &1.columns, else: []))
      |> MapSet.new(& &1.name)

    columns =
      for %{source: {kind, ^name}} = column <- pre_entry.columns,
          kind in stored_kinds(op),
          MapSet.member?(next_columns, column.name),
          do: column

    join_tables =
      if op.op == :delete_relationship do
        kept_join_tables(
          %{join_tables: Enum.filter(pre_entry.join_tables, &(&1.relationship == name))},
          next_join_tables
        )
      else
        []
      end

    cleared = clear_columns(term, pre_entry.table, columns)

    %{cleared | tables: Map.drop(cleared.tables, join_tables)}
  end

  defp companions(mapping, op) do
    {_entity_type, entity_mapping} =
      Enum.find(mapping, fn {_entity_type, entry} -> entry.table == op.table end)

    # A relationship's column holds an id, which has no companions.
    case Enum.find(entity_mapping.columns, &(&1.name == op.column)).source do
      {:attribute, name} ->
        for %{source: {kind, ^name}} = column <- entity_mapping.columns,
            kind in [:search_key, :sort_key],
            do: {kind, column.name}

      {:relationship, _name} ->
        []
    end
  end

  # The renamed member's derivations live under its new name afterwards, so the pairing
  # follows the rename rather than the name - on the entity type the op names only, since
  # another type may declare members under the same names and keeps them.
  defp corresponding_source(
         {:attribute, name},
         entity_type,
         %{op: :rename_attribute, entity: entity_type, from: name} = op
       ) do
    {:attribute, op.to}
  end

  defp corresponding_source(
         {:relationship, name},
         entity_type,
         %{op: :rename_relationship, entity: entity_type, from: name} = op
       ) do
    {:relationship, op.to}
  end

  # A companion follows its attribute through a rename as a RENAME COLUMN - a key does not
  # depend on the attribute's name, so the rows keep theirs.
  defp corresponding_source(
         {kind, name},
         entity_type,
         %{op: :rename_attribute, entity: entity_type, from: name} = op
       )
       when kind in [:search_key, :sort_key] do
    {kind, op.to}
  end

  defp corresponding_source(source, _entity_type, _op), do: source

  defp computed?(%{op: kind, opts: opts}) when kind in [:add_attribute, :add_relationship] do
    match?(%Value{}, opts[:backfill])
  end

  defp computed?(%{op: kind, changes: changes})
       when kind in [:change_attribute, :change_relationship] do
    match?(%Value{}, changes[:backfill])
  end

  defp computed?(_op), do: false

  # A member added again under the name is another one, which the deleted add's backfill mustn't
  # reach.
  defp deleted_later?(%{entity: entity, name: name, op: kind}, later_ops) do
    delete =
      if kind in [:add_attribute, :change_attribute],
        do: :delete_attribute,
        else: :delete_relationship

    Enum.any?(later_ops, &(&1.op == delete and &1.entity == entity and &1.name == name))
  end

  # A tightening's backfill, even a constant, fills the rows as the ops above it left them, so it
  # never merges with a type change of the same attribute in the op next to it.
  defp fills_apart?(%{op: kind, changes: changes})
       when kind in [:change_attribute, :change_relationship] do
    carries_backfill?(changes)
  end

  defp fills_apart?(op), do: computed?(op)

  # The type a to-one's id must exist in, nil for an attribute.
  defp fill_target(%{op: kind} = op, next_model)
       when kind in [:add_relationship, :change_relationship] do
    {:relationship, {_name, target, _opts}} = Value.fill_member(op, next_model)

    target
  end

  defp fill_target(_op, _next_model), do: nil

  defp filled_type(%{op: :add_attribute, type: type}, _next_model), do: type

  defp filled_type(%{op: kind}, _next_model)
       when kind in [:add_relationship, :change_relationship] do
    :uuid
  end

  defp filled_type(op, next_model) do
    {_name, type, _opts} = List.keyfind!(next_model.entities[op.entity].attributes, op.name, 0)

    type
  end

  defp member_column(entry, %{op: kind, name: name}) do
    source_kind =
      if kind in [:add_attribute, :change_attribute], do: :attribute, else: :relationship

    Enum.find(entry.columns, &(&1.source == {source_kind, name}))
  end

  defp entity_after(entity_type, %{op: :rename_entity, from: entity_type} = op), do: op.to

  defp entity_after(entity_type, _op), do: entity_type

  defp enum_type_of(mapping, entity_type, attribute) do
    mapping
    |> Map.fetch!(entity_type)
    |> Map.fetch!(:columns)
    |> Enum.find(&(&1.source == {:attribute, attribute}))
    |> Map.fetch!(:sql_type)
  end

  # The value ops the grant store and the enum attributes take: a role rename moves a
  # value of the grant store's role type, an entity rename moves one of its entity_type
  # (the value IS the entity type module), and an enum value rename moves one of the
  # attribute's own type. Rows follow the label in every case. A grant's id is derived from
  # its labels, though, so the grants a rename relabels take the ids their new labels derive
  # right after it (grant_relabel_ops/5).
  defp enum_value_ops(%{op: :rename_entity} = op, pre_mapping, post_mapping) do
    from = Codec.encode(op.from, :enum)
    to = Codec.encode(op.to, :enum)

    pre_mapping
    |> relabel_ops(post_mapping, :entity_type, from, to)
    |> grant_relabel_ops(post_mapping, :entity_type, from, to)
  end

  defp enum_value_ops(%{op: :rename_enum_value} = op, _pre_mapping, post_mapping) do
    [
      %{
        op: :rename_enum_value,
        enum_type: enum_type_of(post_mapping, op.entity, op.attribute),
        from: Codec.encode(op.from, :enum),
        to: Codec.encode(op.to, :enum)
      }
    ]
  end

  # An entity role name is shared: the store tells :editor on one type from :editor on
  # another by entity_type, not by the enum value, which is deduplicated across the
  # model. So renaming one entity's role relabels every type's grants unless the rows are
  # remapped within that entity_type - and the value has to survive for the others.
  defp enum_value_ops(%{op: :rename_role, entity: entity_type} = op, pre_mapping, post_mapping) do
    from = Codec.encode(op.from, :enum)
    to = Codec.encode(op.to, :enum)

    relabel_ops =
      if from in role_values(post_mapping) do
        scoped_role_rebuild_ops(post_mapping, entity_type, from, to)
      else
        relabel_ops(pre_mapping, post_mapping, :role, from, to)
      end

    grant_relabel_ops(relabel_ops, post_mapping, :role, from, to)
  end

  # A global role's value is its module name, which no entity role can collide with, so
  # renaming one always moves a value nothing else holds.
  defp enum_value_ops(%{op: :rename_role} = op, pre_mapping, post_mapping) do
    from = Codec.encode(op.from, :enum)
    to = Codec.encode(op.to, :enum)

    pre_mapping
    |> relabel_ops(post_mapping, :role, from, to)
    |> grant_relabel_ops(post_mapping, :role, from, to)
  end

  defp enum_value_ops(_op, _pre_mapping, _post_mapping), do: []

  # The relabel, then the re-derivation of the ids of the grants it moved, which the migrator
  # runs - PostgreSQL has no SHA-1 of its own to derive them in SQL. The rows to look at are the
  # ones holding the new label, which is every row the relabel moved, scoped or not; a row that
  # held it already derives the id it has. Right after each relabel rather than once per file:
  # every row's id matches its labels again before the next rename, so a file swapping two
  # labels through a third never moves an id onto one another row still holds.
  # The label the grants held before rides along for a refusal to name them by - the file's
  # transaction takes the relabel back with it, so it is the label they hold again, unless an
  # earlier rename in the same file moved them to it.
  defp grant_relabel_ops([], _post_mapping, _attribute, _from, _to), do: []

  defp grant_relabel_ops(relabel_ops, post_mapping, attribute, from, to) do
    grant_entry = Map.fetch!(post_mapping, RoleGrant)

    rederive_op = %{
      op: :rederive_grant_ids,
      table: grant_entry.table,
      column: role_grant_column(grant_entry, attribute).name,
      from: from,
      value: to
    }

    Enum.concat(relabel_ops, [rederive_op])
  end

  # Every derived name of the entity, paired before and after the rename - whatever
  # differs is renamed. The table goes first, so the column and constraint renames that
  # follow already name it as it now stands.
  defp physical_renames(entity_type, pre_entity, post_entity, op) do
    table = post_entity.table

    table_ops = name_op(:rename_table, nil, pre_entity.table, post_entity.table)

    pk_ops =
      name_op(:rename_constraint, table, pre_entity.pk_constraint, post_entity.pk_constraint)

    column_pairs = column_pairs(entity_type, pre_entity, post_entity, op)

    column_ops =
      Enum.flat_map(column_pairs, fn {pre_column, post_column} ->
        column_renames(pre_column, post_column, table)
      end)

    join_table_ops =
      Enum.flat_map(pre_entity.join_tables, fn pre_join ->
        {:relationship, name} =
          corresponding_source({:relationship, pre_join.relationship}, entity_type, op)

        post_join = Enum.find(post_entity.join_tables, &(&1.relationship == name))

        if post_join, do: join_table_renames(pre_join, post_join), else: []
      end)

    index_ops = index_renames(pre_entity, post_entity, column_pairs)

    table_ops ++ pk_ops ++ column_ops ++ join_table_ops ++ index_ops
  end

  # Declared columns and their derived companions pair by source: the system ones share the
  # :system source and carry fixed names, so they never take part in a rename.
  defp column_pairs(entity_type, pre_entity, post_entity, op) do
    pre_entity.columns
    |> Enum.filter(&paired?/1)
    |> Enum.flat_map(fn pre_column ->
      source = corresponding_source(pre_column.source, entity_type, op)

      case Enum.find(post_entity.columns, &(&1.source == source)) do
        nil -> []
        post_column -> [{pre_column, post_column}]
      end
    end)
  end

  # The entity's own indexes - a unique attribute's or a unique to-one's, and the framework's -
  # carry no source of their own, so each pairs with the index over the same columns after the
  # rename, a renamed column counting as the column it became. PostgreSQL keeps an index on a
  # column through a rename of the column or of its table, so only the name is left to follow.
  defp index_renames(pre_entity, post_entity, column_pairs) do
    column_names =
      Map.new(column_pairs, fn {pre_column, post_column} ->
        {pre_column.name, post_column.name}
      end)

    Enum.flat_map(pre_entity.indexes, fn {pre_name, pre_index} ->
      columns = Enum.map(pre_index.columns, &Map.get(column_names, &1, &1))

      case Enum.find(post_entity.indexes, &same_index?(&1, columns, pre_index.unique)) do
        {post_name, _post_index} -> name_op(:rename_index, nil, pre_name, post_name)
        nil -> []
      end
    end)
  end

  defp paired?(%{source: {kind, _name}})
       when kind in [:attribute, :relationship, :search_key, :sort_key],
       do: true

  defp paired?(_column), do: false

  defp same_index?({_name, index}, columns, unique?) do
    index.columns == columns and index.unique == unique?
  end

  defp column_renames(pre_column, post_column, table) do
    name_op(:rename_column, table, pre_column.name, post_column.name) ++
      name_op(:rename_constraint, table, pre_column.fk_constraint, post_column.fk_constraint) ++
      enum_type_renames(pre_column, post_column)
  end

  defp enum_type_renames(%{type: :enum} = pre_column, post_column) do
    name_op(:rename_enum_type, nil, pre_column.sql_type, post_column.sql_type)
  end

  defp enum_type_renames(_pre_column, _post_column), do: []

  defp join_table_renames(pre_join, post_join) do
    table = post_join.name

    name_op(:rename_table, nil, pre_join.name, post_join.name) ++
      name_op(:rename_constraint, table, pre_join.pk_constraint, post_join.pk_constraint) ++
      name_op(
        :rename_constraint,
        table,
        pre_join.source_fk_constraint,
        post_join.source_fk_constraint
      ) ++
      name_op(
        :rename_constraint,
        table,
        pre_join.target_fk_constraint,
        post_join.target_fk_constraint
      )
  end

  defp name_op(_kind, _table, same, same), do: []

  defp name_op(_kind, _table, nil, _to), do: []

  defp name_op(:rename_constraint, table, from, to) do
    [%{op: :rename_constraint, table: table, from: from, to: to}]
  end

  defp name_op(:rename_column, table, from, to) do
    [%{op: :rename_column, table: table, from: from, to: to}]
  end

  defp name_op(kind, _table, from, to), do: [%{op: kind, from: from, to: to}]

  defp place_op(op, []), do: [{if(fills_apart?(op), do: op), [op]}]

  defp place_op(op, [{cut, [last | _earlier] = current} | done] = placed) do
    cond do
      fills_apart?(op) or recreates_entity?(op, current) -> [{op, [op]} | placed]
      fills_apart?(last) or segment_kind(op) != segment_kind(last) -> [{nil, [op]} | placed]
      true -> [{cut, [op | current]} | done]
    end
  end

  defp put_backfill(%{op: :add_column} = op, backfills) do
    case Map.fetch(backfills, {op.table, op.column}) do
      {:ok, {value, _target}} -> Map.put(op, :backfill, value)
      :error -> op
    end
  end

  defp put_backfill(%{op: :alter_column} = op, backfills) do
    case Map.fetch(backfills, {op.table, op.column}) do
      {:ok, {value, target}} ->
        Map.merge(op, %{fill: value, fill_source: :backfill, fill_target: target})

      :error ->
        op
    end
  end

  # The constant is already in the column when the key is added, so the add is what meets an id
  # no row holds.
  defp put_backfill(%{op: :add_foreign_key} = op, backfills) do
    case Map.fetch(backfills, {op.table, op.column}) do
      {:ok, {_value, target}} -> Map.put(op, :fill_target, target)
      :error -> op
    end
  end

  defp put_backfill(op, _backfills), do: op

  # Looked up in the mapping the op's own chunk leaves, where the column still has the name
  # the op adds it under - a default changed in the same chunk counts, one changed after a
  # later rename does not. An explicit backfill wins: it says what the rows that predate the
  # column receive, the default what every row receives when the app supplies nothing.
  defp put_declared_default(%{op: :add_column, definition: %{null: false}} = op, mapping)
       when not is_map_key(op, :backfill) do
    case Preflight.fill_value(mapping, op.table, op.column) do
      {:ok, value} ->
        validate_default_held!(op, value, mapping)
        Map.put(op, :backfill, value)

      :none ->
        op
    end
  end

  # A tightening's own backfill wins over the declared default, and only needs the companions.
  defp put_declared_default(%{op: :alter_column, fill: _value} = op, mapping) do
    Map.put(op, :fill_companions, companions(mapping, op))
  end

  # A column turning required the same way: its NULLs take the declared default before it
  # tightens. Not with a type change in the same op - the default holds a new-type value
  # while the column still has the old type, so such a change meets its NULLs unfilled.
  # The op also names the column's companions as they stand here, which the filled rows'
  # keys go into.
  defp put_declared_default(
         %{
           op: :alter_column,
           before: %{null: true, type: type},
           after: %{null: false, type: type}
         } = op,
         mapping
       ) do
    case Preflight.fill_value(mapping, op.table, op.column) do
      {:ok, value} ->
        Map.merge(op, %{
          default_held: default_held?(op, value, mapping),
          fill: value,
          fill_companions: companions(mapping, op)
        })

      :none ->
        op
    end
  end

  defp put_declared_default(op, _mapping), do: op

  # Both of the grant store's enums derive their values SORTED, and PostgreSQL orders a type by
  # the POSITION of a value rather than by its label - while ALTER TYPE ... RENAME VALUE moves the
  # label and leaves the position alone. So a rename whose new label sorts elsewhere leaves the
  # database holding the right values in the wrong order, which the drift check refuses on the
  # next boot - after the file has committed, so nothing revisits it and no generated migration
  # can repair it. Such a rename is rendered as a type REBUILD instead, carrying the rows over
  # with an unscoped remap: the value is a table name or a global role's module name, which
  # nothing else holds, so every row holding it is a row that follows the rename.
  #
  # The cheap in-place rename is kept for the case it is correct for - a new label that sorts
  # where the old one sat - because a rebuild rewrites the column.
  defp relabel_ops(pre_mapping, post_mapping, attribute, from, to) do
    if Map.has_key?(pre_mapping, RoleGrant) and Map.has_key?(post_mapping, RoleGrant) do
      pre_column = role_grant_column(Map.fetch!(pre_mapping, RoleGrant), attribute)
      post_entry = Map.fetch!(post_mapping, RoleGrant)
      post_column = role_grant_column(post_entry, attribute)
      renamed_in_place = Enum.map(pre_column.enum_values, &if(&1 == from, do: to, else: &1))

      if renamed_in_place == post_column.enum_values do
        rename_enum_value_ops(post_mapping, attribute, from, to)
      else
        [
          %{
            op: :rebuild_enum_type,
            enum_type: post_column.sql_type,
            values: post_column.enum_values,
            columns: [{post_entry.table, post_column.name}],
            remap: [%{from: from, to: to, scope: nil}]
          }
        ]
      end
    else
      rename_enum_value_ops(post_mapping, attribute, from, to)
    end
  end

  # By table, since two modules can derive one name, as MyApp.TaskItem and MyApp.Task.Item do.
  defp recreates_entity?(%{op: :create_entity, entity: entity}, ops) do
    table = Mapper.table_name(entity)

    Enum.any?(ops, &(&1.op == :delete_entity and Mapper.table_name(&1.entity) == table))
  end

  # The create above it is left to stand alone, which the mapper refuses on the shared table.
  defp recreates_entity?(%{op: :delete_entity, entity: entity}, ops) do
    table = Mapper.table_name(entity)

    Enum.any?(ops, fn op ->
      op.op == :create_entity and op.entity != entity and Mapper.table_name(op.entity) == table
    end)
  end

  defp recreates_entity?(_op, _ops), do: false

  defp role_values(mapping) do
    case Map.fetch(mapping, RoleGrant) do
      {:ok, entry} -> role_grant_column(entry, :role).enum_values
      :error -> []
    end
  end

  defp role_grant_column(entry, attribute) do
    Enum.find(entry.columns, &(&1.source == {:attribute, attribute}))
  end

  # The rebuild rather than a value rename: the old value stays for the entity types that
  # still declare it, the new one arrives beside it, and only the rows scoped to this
  # entity type follow. A fresh type also sidesteps PostgreSQL refusing to use a value added
  # by ALTER TYPE in the transaction that added it.
  defp scoped_role_rebuild_ops(mapping, entity_type, from, to) do
    grant_entry = Map.fetch!(mapping, RoleGrant)
    role_column = role_grant_column(grant_entry, :role)
    entity_type_column = role_grant_column(grant_entry, :entity_type)

    [
      %{
        op: :rebuild_enum_type,
        enum_type: role_column.sql_type,
        values: role_column.enum_values,
        columns: [{grant_entry.table, role_column.name}],
        remap: [
          %{
            from: from,
            to: to,
            scope: {entity_type_column.name, Codec.encode(entity_type, :enum)}
          }
        ]
      }
    ]
  end

  defp rename_enum_value_ops(mapping, attribute, from, to) do
    if Map.has_key?(mapping, RoleGrant) do
      [
        %{
          op: :rename_enum_value,
          enum_type: enum_type_of(mapping, RoleGrant, attribute),
          from: from,
          to: to
        }
      ]
    else
      []
    end
  end

  defp render_chunk([%{op: :change_relationship} = first | _rest] = chunk, model) do
    cond do
      retarget?(first) ->
        Enum.reduce(chunk, {[], model}, fn op, {acc, current_model} ->
          next_model = Model.fold(current_model, [op])

          {acc ++ retarget_ops_for(op, current_model, next_model), next_model}
        end)

      computed?(first) ->
        render_computed_tightening(first, model)

      true ->
        render_plain_chunk(chunk, model)
    end
  end

  defp render_chunk([%{op: kind} = op] = chunk, model)
       when kind in [:add_attribute, :add_relationship] do
    if computed?(op), do: render_computed_add(op, model), else: render_plain_chunk(chunk, model)
  end

  defp render_chunk([%{op: kind} | _rest] = chunk, model) when kind in @rename_ops do
    Enum.reduce(chunk, {[], model}, fn op, {acc, current_model} ->
      next_model = Model.fold(current_model, [op])

      {acc ++ rename_ops_for(op, current_model, next_model), next_model}
    end)
  end

  defp render_chunk([%{op: :change_attribute} = op] = chunk, model) do
    if computed?(op),
      do: render_computed_tightening(op, model),
      else: render_plain_chunk(chunk, model)
  end

  defp render_chunk(chunk, model), do: render_plain_chunk(chunk, model)

  defp render_chunks(chunks, pre_model) do
    validate_cuts!(chunks, pre_model)

    Enum.reduce(chunks, {[], pre_model}, fn {_cut, chunk}, {acc, model} ->
      {ops, next_model} = render_chunk(chunk, model)

      {acc ++ mark_tightenings(ops, chunk, model, next_model), next_model}
    end)
  end

  # A tightening nothing fills is refused over rows holding nil, naming what the member can take.
  defp mark_tightenings(ops, chunk, model, next_model) do
    if Enum.any?(ops, &unfilled_tightening?/1) do
      # The chunk's start, where a column being altered stands: a later op of the chunk can drop it.
      mapping = Mapper.derive_from_model!(model)

      Enum.map(ops, &mark_tightening(&1, chunk, mapping, next_model))
    else
      ops
    end
  end

  defp mark_tightening(op, chunk, mapping, next_model) do
    if unfilled_tightening?(op),
      do: Map.put(op, :tightening, tightening(op, chunk, mapping, next_model)),
      else: op
  end

  defp tightening(op, chunk, mapping, next_model) do
    {entity_type, kind, name} = column_member(mapping, op.table, op.column)

    # A declared default fills a tightening only when the column keeps its type.
    takes_default =
      kind == :attribute and op.before.type == op.after.type and
        not unique_attribute?(next_model, entity_type, name)

    %{
      kind: kind,
      takes_default: takes_default,
      type_stated: Enum.any?(chunk, &states_type?(&1, entity_type, name))
    }
  end

  defp states_type?(
         %{op: kind, entity: entity_type, name: name, changes: changes},
         entity_type,
         name
       )
       when kind in [:change_attribute, :change_relationship] do
    Keyword.has_key?(changes, :type)
  end

  defp states_type?(_op, _entity_type, _name), do: false

  defp unique_attribute?(model, entity_type, name) do
    case List.keyfind(model.entities[entity_type][:attributes] || [], name, 0) do
      {^name, _type, opts} -> opts[:unique] == true
      nil -> false
    end
  end

  # A required add nothing fills is refused over rows the way a tightening is, naming what the
  # member can take. A declared default fills an add whatever type the chunk gives it.
  defp mark_unfilled_add(
         %{op: :add_column, definition: %{null: false}} = op,
         chunk,
         mapping,
         model
       )
       when not is_map_key(op, :backfill) do
    {entity_type, kind, name} = column_member(mapping, op.table, op.column)

    unfilled = %{
      kind: kind,
      takes_default: kind == :attribute and not unique_attribute?(model, entity_type, name),
      type_stated: Enum.any?(chunk, &states_type?(&1, entity_type, name))
    }

    Map.put(op, :unfilled, unfilled)
  end

  defp mark_unfilled_add(op, _chunk, _mapping, _model), do: op

  # The entity type, kind and name of the member the given table's column stores.
  defp column_member(mapping, table, column) do
    {entity_type, entry} = Enum.find(mapping, fn {_type, entry} -> entry.table == table end)
    {kind, name} = Enum.find(entry.columns, &(&1.name == column)).source

    {entity_type, kind, name}
  end

  defp unfilled_tightening?(
         %{op: :alter_column, before: %{null: true}, after: %{null: false}} = op
       ) do
    not Map.has_key?(op, :fill) and not Map.has_key?(op, :filled)
  end

  defp unfilled_tightening?(_op), do: false

  # Added nullable, filled, then tightened. The tightening is marked filled and takes no declared
  # default: the expression said what each row holds, so a NULL it left is refused rather than
  # replaced.
  defp render_computed_add(op, model) do
    next_model = Model.fold(model, [op], validate_filled_adds: false)
    next_mapping = Mapper.derive_from_model!(next_model)
    entry = Map.fetch!(next_mapping, op.entity)
    column = member_column(entry, op)

    diff_ops =
      model
      |> term()
      |> Schema.diff(Schema.from_mapping(next_mapping), renames: false)

    # A chunk of one add leaves its table standing, so the diff always adds the column.
    %{definition: definition} =
      add_op =
      Enum.find(diff_ops, fn diff_op ->
        diff_op.op == :add_column and diff_op.table == entry.table and
          diff_op.column == column.name
      end)

    nullable = %{definition | null: true}

    added_ops =
      Enum.map(diff_ops, &if(&1 == add_op, do: %{add_op | definition: nullable}, else: &1))

    fill_op =
      op
      |> fill_column_op(model, next_model, next_mapping, entry.table, column.name)
      |> Map.put(:required, not definition.null)

    tighten_ops =
      if definition.null do
        []
      else
        [
          %{
            op: :alter_column,
            table: entry.table,
            column: column.name,
            before: nullable,
            after: definition,
            filled: true
          }
        ]
      end

    {added_ops ++ [fill_op] ++ tighten_ops, next_model}
  end

  # The column stands, so only the rows holding nil fill, right before it tightens. The fold has
  # refused a member already required, so the diff always holds the tightening.
  defp render_computed_tightening(op, model) do
    next_model = Model.fold(model, [op], validate_filled_adds: false)
    next_mapping = Mapper.derive_from_model!(next_model)
    entry = Map.fetch!(next_mapping, op.entity)
    table = entry.table
    column = member_column(entry, op).name

    fill_op =
      op
      |> fill_column_op(model, next_model, next_mapping, table, column)
      |> Map.merge(%{
        companions: companions(next_mapping, %{table: table, column: column}),
        required: true
      })

    diff_ops =
      model
      |> term()
      |> Schema.diff(Schema.from_mapping(next_mapping), renames: false)

    %{op: :alter_column} =
      tightening =
      Enum.find(diff_ops, &match?(%{op: :alter_column, table: ^table, column: ^column}, &1))

    physical_ops =
      Enum.flat_map(diff_ops, fn
        ^tightening -> [fill_op, Map.put(tightening, :filled, true)]
        other -> [other]
      end)

    {physical_ops, next_model}
  end

  defp fill_column_op(op, model, next_model, mapping, table, column) do
    [%{backfill: {:computed, value}, kind: kind, nulls_only: nulls_only}] =
      Value.fills([op], model)

    {^kind, {_name, type, rules} = member} = Value.fill_member(op, next_model)
    target = Value.fill_target(kind, member, op)

    Map.merge(
      %{
        op: :fill_column,
        table: table,
        column: column,
        companions: [],
        entity: op.entity,
        fill_target: fill_target(op, next_model),
        line: op.line,
        mapping: mapping,
        max_bytes: Map.get(op, :max_bytes),
        member: op.name,
        nulls_only: nulls_only,
        rules: rules,
        type: type
      },
      fill_source(value, op, mapping, column, target)
    )
  end

  # An Elixir fn has no SQL, so the op names what the row-by-row fill reads and writes. It can
  # return any value of an enum, so all of them count as used.
  defp fill_source(%{term: {:function, module, function, args}}, op, mapping, column, _target) do
    entry = Map.fetch!(mapping, op.entity)
    filled = Enum.find(entry.columns, &(&1.name == column))

    %{
      arg_columns:
        Enum.map(args, fn name ->
          arg_column = QueryCompiler.name_column(entry, name)

          {arg_column.name, arg_column.type}
        end),
      column_sql_type: filled.sql_type,
      column_type: filled.type,
      enum_uses: Enum.map(filled.enum_values || [], &{filled.sql_type, &1}),
      function: {module, function},
      sort_keys: []
    }
  end

  defp fill_source(value, op, mapping, _column, target) do
    %{
      enum_uses: SQL.enum_uses(value, op.entity, mapping, target),
      sort_keys: SQL.sort_keys(value, op.entity, mapping),
      sql: SQL.render(value, op.entity, mapping, target)
    }
  end

  # Every Schema.diff here passes renames: false. A migration says what it renames in its
  # model ops, and the rename chunks pair those from the mapping - pairing by definition could
  # turn a relationship deleted and another added in one plain chunk into a rename the file
  # never stated.
  defp render_plain_chunk(chunk, model) do
    next_model = Model.fold(model, chunk, validate_filled_adds: false)
    next_mapping = Mapper.derive_from_model!(next_model)
    pre_mapping = Mapper.derive_from_model!(model)
    pre_term = Schema.from_mapping(pre_mapping)
    cleared_term = without_recreated(pre_term, chunk, pre_mapping, next_mapping)

    physical_ops =
      pre_term
      |> Schema.diff(cleared_term, renames: false)
      |> Enum.concat(Schema.diff(cleared_term, Schema.from_mapping(next_mapping), renames: false))
      |> attach_backfills(chunk, next_model, next_mapping)
      |> Enum.map(&put_declared_default(&1, next_mapping))
      |> Enum.map(&mark_unfilled_add(&1, chunk, next_mapping, next_model))
      |> prepend_grant_deletes(chunk)

    {physical_ops, next_model}
  end

  # The op deletes rows, so it folds to nothing and the schema diff cannot see it - the
  # physical form is added here instead. FIRST, because the designation change it
  # accompanies re-points the store's foreign keys, and the new keys validate against the
  # rows still standing: emptying the store after them is emptying it too late.
  defp prepend_grant_deletes(physical_ops, chunk) do
    if Enum.any?(chunk, &(&1.op == :delete_role_grants)) do
      [%{op: :delete_role_grants, table: Mapper.table_name(RoleGrant)} | physical_ops]
    else
      physical_ops
    end
  end

  # A cardinality change moves data, which no schema difference expresses: the join table
  # has to exist before the reference values move into it, and the old column has to
  # survive until they have. The phase order the schema diff applies would drop it first.
  defp retarget_ops_for(op, pre_model, post_model) do
    pre_type = relationship_type(pre_model, op.entity, op.name)
    post_type = relationship_type(post_model, op.entity, op.name)

    case {pre_type, post_type} do
      {[_target], to_one} when not is_list(to_one) ->
        raise_narrowing!(op)

      {to_one, [_target]} when not is_list(to_one) ->
        widen_ops(op, pre_model, post_model)

      _same_cardinality ->
        pre_model
        |> term()
        |> Schema.diff(term(post_model), renames: false)
    end
  end

  defp retarget?(%{op: :change_relationship} = op), do: Keyword.has_key?(op.changes, :type)

  defp retarget?(_op), do: false

  defp relationship_type(model, entity_type, name) do
    model.entities
    |> Map.fetch!(entity_type)
    |> Map.fetch!(:relationships)
    |> Enum.find_value(fn {member_name, type, _opts} -> member_name == name && type end)
  end

  defp raise_narrowing!(op) do
    raise Hologram.CompileError,
      message:
        "changing relationship #{inspect(op.name)} on #{inspect(op.entity)} " <>
          "from to-many to to-one is not supported - a row holding several targets " <>
          "has no one target to keep - delete the relationship and add it with the " <>
          "new cardinality, or write the migration that picks the survivors"
  end

  defp segment_kind(op) do
    cond do
      op.op in @rename_ops -> :rename
      retarget?(op) -> :retarget
      true -> :plain
    end
  end

  # The join table first, then the reference values, then the column they came from.
  defp widen_ops(op, pre_model, post_model) do
    physical_ops =
      pre_model
      |> term()
      |> Schema.diff(term(post_model), renames: false)

    {drops, creates} = Enum.split_with(physical_ops, &(&1.op in @drop_ops))
    mapping = Mapper.derive_from_model!(pre_model)
    entity_mapping = Map.fetch!(mapping, op.entity)
    column = Enum.find(entity_mapping.columns, &(&1.source == {:relationship, op.name}))

    join_table =
      post_model
      |> Mapper.derive_from_model!()
      |> Map.fetch!(op.entity)
      |> Map.fetch!(:join_tables)
      |> Enum.find(&(&1.relationship == op.name))

    widen_op = %{
      op: :widen_to_many,
      table: entity_mapping.table,
      join_table: join_table.name,
      column: column.name
    }

    creates ++ [widen_op] ++ drops
  end

  defp rename_ops_for(op, pre_model, post_model) do
    pre_mapping = Mapper.derive_from_model!(pre_model)
    post_mapping = Mapper.derive_from_model!(post_model)

    entity_ops =
      Enum.flat_map(pre_mapping, fn {entity_type, pre_entity} ->
        post_entity = post_mapping[entity_after(entity_type, op)]

        if post_entity, do: physical_renames(entity_type, pre_entity, post_entity, op), else: []
      end)

    entity_ops ++ enum_value_ops(op, pre_mapping, post_mapping)
  end

  # One forward walk over the file's physical ops, following each to where the rest of the
  # file leaves it.
  #
  # An index on a table born in this file builds inside the transaction - the table is
  # empty, so the build is instant and the file keeps its all-or-nothing shape. Born means
  # born by the index's position in the file: a table renamed away and recreated under its
  # old name later in the file still holds its rows where the index meets it.
  #
  # Any other index builds in the tail, after every op of the file has run, so it has to be
  # the index those ops leave: a rename after it renames the build itself - nothing stands
  # under the old name to rename yet - and a drop after it takes the build back.
  #
  # The added columns are the same: their companions fill after every op has run, so each
  # is named as the file leaves it, and one the file drops again has nothing to fill.
  defp walk_ops(physical_ops) do
    initial = %{added: [], born: MapSet.new(), pending: [], transactional: []}
    walked = Enum.reduce(physical_ops, initial, &walk_op/2)

    tail =
      walked.pending
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :concurrently, true))

    %{
      added_columns: Enum.reverse(walked.added),
      tail: tail,
      transactional: Enum.reverse(walked.transactional)
    }
  end

  defp walk_op(%{op: :add_column} = op, walked) do
    added = %{op: :add_column, table: op.table, column: op.column}

    %{keep_op(op, walked) | added: [added | walked.added]}
  end

  defp walk_op(%{op: :create_index} = op, walked) do
    if MapSet.member?(walked.born, op.table),
      do: keep_op(op, walked),
      else: %{walked | pending: [op | walked.pending]}
  end

  defp walk_op(%{op: :create_table} = op, walked) do
    %{keep_op(op, walked) | born: MapSet.put(walked.born, op.table)}
  end

  defp walk_op(%{op: :drop_column} = op, walked) do
    added = Enum.reject(walked.added, &(&1.table == op.table and &1.column == op.column))

    %{keep_op(op, walked) | added: added}
  end

  defp walk_op(%{op: :drop_index} = op, walked) do
    if Enum.any?(walked.pending, &(&1.index == op.index)),
      do: %{walked | pending: Enum.reject(walked.pending, &(&1.index == op.index))},
      else: keep_op(op, walked)
  end

  # A dropped table takes its indexes with it, and the diff emits no drop for them.
  defp walk_op(%{op: :drop_table} = op, walked) do
    %{
      keep_op(op, walked)
      | added: Enum.reject(walked.added, &(&1.table == op.table)),
        born: MapSet.delete(walked.born, op.table),
        pending: Enum.reject(walked.pending, &(&1.table == op.table))
    }
  end

  # A sort key an earlier op of this file added is filled only after every op, so a fill ordering
  # by it has it filled first. Named by the mapping of the fill's chunk, as the database stands
  # there, since a later rename finds no column under the name the file ends with.
  defp walk_op(%{op: :fill_column} = op, walked) do
    fill_op = Map.drop(op, [:enum_uses, :mapping, :sort_keys])

    case Enum.filter(op.sort_keys, &(&1 in walked.added)) do
      [] ->
        keep_op(fill_op, walked)

      columns ->
        companion_fill = %{op: :fill_companions, columns: columns, mapping: op.mapping}

        keep_op(fill_op, keep_op(companion_fill, walked))
    end
  end

  defp walk_op(%{op: :rename_column} = op, walked) do
    pending =
      Enum.map(walked.pending, fn
        %{table: table} = build when table == op.table ->
          %{build | columns: Enum.map(build.columns, &if(&1 == op.from, do: op.to, else: &1))}

        build ->
          build
      end)

    added =
      Enum.map(walked.added, fn
        %{table: table, column: column} = added when table == op.table and column == op.from ->
          %{added | column: op.to}

        added ->
          added
      end)

    %{keep_op(op, walked) | added: added, pending: pending}
  end

  defp walk_op(%{op: :rename_index} = op, walked) do
    if Enum.any?(walked.pending, &(&1.index == op.from)) do
      pending =
        Enum.map(walked.pending, &if(&1.index == op.from, do: %{&1 | index: op.to}, else: &1))

      %{walked | pending: pending}
    else
      keep_op(op, walked)
    end
  end

  defp walk_op(%{op: :rename_table} = op, walked) do
    born =
      if MapSet.member?(walked.born, op.from) do
        walked.born
        |> MapSet.delete(op.from)
        |> MapSet.put(op.to)
      else
        walked.born
      end

    rename = &if(&1.table == op.from, do: %{&1 | table: op.to}, else: &1)

    %{
      keep_op(op, walked)
      | added: Enum.map(walked.added, rename),
        born: born,
        pending: Enum.map(walked.pending, rename)
    }
  end

  defp walk_op(op, walked), do: keep_op(op, walked)

  defp keep_op(op, walked), do: %{walked | transactional: [op | walked.transactional]}

  defp term(model) do
    model
    |> Mapper.derive_from_model!()
    |> Schema.from_mapping()
  end

  # The model takes some ops' options unchecked, so they may be a map as well as a keyword list.
  defp carries_backfill?(options) do
    options
    |> Map.new()
    |> Map.has_key?(:backfill)
  end

  defp stored_kinds(%{op: :delete_attribute}), do: [:attribute, :search_key, :sort_key]

  defp stored_kinds(%{op: :delete_relationship}), do: [:relationship]

  # The diff keys on physical names, so a member deleted with another added under the same name
  # reads as one column left alone, and with another type as one to convert. Starting the diff
  # from a term without what the deleted member held makes it drop that and create the new one.
  defp without_recreated(term, chunk, pre_mapping, next_mapping) do
    # From every entity type: two can derive one join table name.
    next_join_tables =
      for {_entity_type, entry} <- next_mapping,
          join_table <- entry.join_tables,
          into: MapSet.new(),
          do: join_table.name

    chunk
    |> Enum.filter(&(&1.op in [:delete_attribute, :delete_entity, :delete_relationship]))
    |> Enum.reduce(term, fn op, acc ->
      clear_member(acc, op, pre_mapping[op.entity], next_mapping[op.entity], next_join_tables)
    end)
  end

  defp kept_join_tables(entry, next_join_tables) do
    entry.join_tables
    |> Enum.map(& &1.name)
    |> Enum.filter(&MapSet.member?(next_join_tables, &1))
  end

  # A rename or a computed backfill can part a default from the op bringing its value into the
  # type, which then doesn't hold it when the column fills.
  defp validate_default_held!(op, value, mapping) do
    if not default_held?(op, value, mapping) do
      raise Hologram.CompileError,
        message: Preflight.unheld_default_message(op.table, op.column, value, :add)
    end
  end

  defp default_held?(op, value, mapping) do
    {_entity_type, entry} =
      Enum.find(mapping, fn {_entity_type, entry} -> entry.table == op.table end)

    column = Enum.find(entry.columns, &(&1.name == op.column))

    is_nil(column.enum_values) or value in column.enum_values
  end

  # The whole file passed its fold, but a cut makes the ops on each side of it apply on their own,
  # so what the chunks leave has to stand: a delete and its cleanup, or a relationship and the
  # entity type it targets, can't sit on opposite sides. Asked up front rather than around the
  # rendering, whose other refusals aren't about the cut.
  defp validate_cuts!(chunks, pre_model) do
    if cut?(chunks) do
      cuts = for {cut, _chunk} <- chunks, cut, do: cut

      chunks
      |> Enum.with_index()
      |> Enum.reduce(pre_model, fn {{_cut, chunk}, index}, model ->
        next_model = fold_apart(model, chunk, cuts)

        validate_targets_standing!(next_model, created_after(chunks, index), cuts)

        next_model
      end)
    end
  end

  defp created_after(chunks, index) do
    for {_cut, chunk} <- Enum.drop(chunks, index + 1),
        %{op: :create_entity, entity: entity} <- chunk,
        do: entity
  end

  defp cut?(chunks), do: Enum.any?(chunks, fn {cut, _chunk} -> cut end)

  defp fold_apart(model, chunk, cuts) do
    next_model = Model.fold(model, chunk, validate_filled_adds: false)

    _mapping = Mapper.derive_from_model!(next_model)

    next_model
  rescue
    error in Hologram.CompileError -> raise_apart!(cuts, Exception.message(error))
  end

  defp validate_targets_standing!(model, created_later, cuts) do
    missing =
      for {entity_type, entry} <- model.entities,
          {name, type, _opts} <- entry.relationships,
          target <- [relationship_target(type)],
          target in created_later,
          not Map.has_key?(model.entities, target) do
        "#{inspect(name)} on #{inspect(entity_type)} targets #{inspect(target)}, created below"
      end

    if missing != [] do
      reason =
        missing
        |> Enum.sort()
        |> Enum.join(", ")

      raise_apart!(cuts, reason)
    end
  end

  defp relationship_target([target]), do: target

  defp relationship_target(target), do: target

  @spec raise_apart!(list(%{atom => any}), String.t()) :: no_return
  defp raise_apart!(cuts, reason) do
    raise Hologram.CompileError,
      message:
        "these ops apply apart from the ops around them: " <>
          "#{Enum.map_join(cuts, ", ", &describe_op/1)} - the ops above each have to stand " <>
          "without the ones below it, so move the op completing them above it. " <>
          "Refused without it: #{reason}"
  end

  defp describe_op(%{name: name} = op) do
    "#{op.op} #{inspect(name)} on #{inspect(op.entity)}#{op_line(op)}"
  end

  defp describe_op(%{entity: entity} = op), do: "#{op.op} #{inspect(entity)}#{op_line(op)}"

  defp op_line(%{line: line}), do: " (line #{line})"

  defp op_line(_op), do: ""
end
