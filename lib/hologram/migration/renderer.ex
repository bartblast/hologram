defmodule Hologram.Migration.Renderer do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.DB.Preflight
  alias Hologram.DB.Schema
  alias Hologram.Entity.Model
  alias Hologram.Migration.Value

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

    Enum.each(logical_ops, &validate_backfill_applies!/1)

    {physical_ops, post_model} =
      logical_ops
      |> Enum.chunk_by(&segment_kind/1)
      |> Enum.reduce({[], pre_model}, fn chunk, {acc, model} ->
        {ops, next_model} = render_chunk(chunk, model)

        {acc ++ ops, next_model}
      end)

    physical_ops
    |> walk_ops()
    |> Map.put(:post_model, post_model)
  end

  # A backfill rides its logical op, never the model - the physical column it fills is
  # found by the name the mapper derives for that attribute.
  defp attach_backfills(physical_ops, logical_ops) do
    backfills =
      for %{op: :add_attribute} = op <- logical_ops,
          {:ok, value} <- [Keyword.fetch(op.opts, :backfill)],
          into: %{} do
        {{Mapper.table_name(op.entity), Atom.to_string(op.name)}, Codec.encode(value, op.type)}
      end

    Enum.map(physical_ops, &put_backfill(&1, backfills))
  end

  defp companions(mapping, op) do
    {_entity_type, entity_mapping} =
      Enum.find(mapping, fn {_entity_type, entry} -> entry.table == op.table end)

    {:attribute, name} = Enum.find(entity_mapping.columns, &(&1.name == op.column)).source

    for %{source: {kind, ^name}} = column <- entity_mapping.columns,
        kind in [:search_key, :sort_key],
        do: {kind, column.name}
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

  defp put_backfill(%{op: :add_column} = op, backfills) do
    case Map.fetch(backfills, {op.table, op.column}) do
      {:ok, value} -> Map.put(op, :backfill, value)
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
      {:ok, value} -> Map.put(op, :backfill, value)
      :none -> op
    end
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
      {:ok, value} -> Map.merge(op, %{fill: value, fill_companions: companions(mapping, op)})
      :none -> op
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
    if retarget?(first) do
      Enum.reduce(chunk, {[], model}, fn op, {acc, current_model} ->
        next_model = Model.fold(current_model, [op])

        {acc ++ retarget_ops_for(op, current_model, next_model), next_model}
      end)
    else
      render_plain_chunk(chunk, model)
    end
  end

  defp render_chunk([%{op: kind} | _rest] = chunk, model) when kind in @rename_ops do
    Enum.reduce(chunk, {[], model}, fn op, {acc, current_model} ->
      next_model = Model.fold(current_model, [op])

      {acc ++ rename_ops_for(op, current_model, next_model), next_model}
    end)
  end

  defp render_chunk(chunk, model), do: render_plain_chunk(chunk, model)

  # Every Schema.diff here passes renames: false. A migration says what it renames in its
  # model ops, and the rename chunks pair those from the mapping - pairing by definition could
  # turn a relationship deleted and another added in one plain chunk into a rename the file
  # never stated.
  defp render_plain_chunk(chunk, model) do
    next_model = Model.fold(model, chunk, validate_filled_adds: false)
    next_mapping = Mapper.derive_from_model!(next_model)

    physical_ops =
      model
      |> term()
      |> Schema.diff(Schema.from_mapping(next_mapping), renames: false)
      |> attach_backfills(chunk)
      |> Enum.map(&put_declared_default(&1, next_mapping))
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

  # A backfill the ops below can't apply is refused rather than dropped without a word.
  defp validate_backfill_applies!(%{op: :add_attribute, opts: opts} = op) do
    if match?(%Value{}, opts[:backfill]), do: raise_unapplied_backfill!(op)
  end

  defp validate_backfill_applies!(%{op: :add_relationship, opts: opts} = op) do
    if carries_backfill?(opts), do: raise_unapplied_backfill!(op)
  end

  defp validate_backfill_applies!(%{op: kind, changes: changes} = op)
       when kind in [:change_attribute, :change_relationship] do
    if carries_backfill?(changes), do: raise_unapplied_backfill!(op)
  end

  defp validate_backfill_applies!(_op), do: :ok

  @spec raise_unapplied_backfill!(%{atom => any}) :: no_return
  defp raise_unapplied_backfill!(op) do
    raise Hologram.CompileError,
      message:
        "#{op.op} #{inspect(op.name)} of #{inspect(op.entity)} on line #{op.line} carries a " <>
          "backfill that can't be applied yet - only a constant on add_attribute can for now"
  end
end
