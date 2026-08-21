defmodule Hologram.Migration.Renderer do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.DB.Schema
  alias Hologram.Entity.Model

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
  go concurrently, which PostgreSQL forbids inside a transaction.

  The ops render through the mapping: the model before and after them project to physical
  schema terms, and their difference is what the database must do. Physical names
  therefore never enter the migration history - a change to the derived-name rules
  changes what the same history renders to. Rendering the ops together rather than one by
  one keeps the statements minimal: an entity arriving with its attributes is one CREATE
  TABLE, not a table followed by a column at a time.
  """
  @spec render(list(%{atom => any}), %{atom => any}) :: %{atom => any}
  def render(logical_ops, pre_model) do
    {physical_ops, post_model} =
      logical_ops
      |> Enum.chunk_by(&segment_kind/1)
      |> Enum.reduce({[], pre_model}, fn chunk, {acc, model} ->
        {ops, next_model} = render_chunk(chunk, model)

        {acc ++ ops, next_model}
      end)

    born_here = born_here(physical_ops)
    {transactional, tail} = Enum.split_with(physical_ops, &(not concurrent?(&1, born_here)))

    %{
      transactional: transactional,
      tail: Enum.map(tail, &Map.put(&1, :concurrently, true)),
      post_model: post_model
    }
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

  defp born_here(ops) do
    for %{op: :create_table, table: table} <- ops, into: MapSet.new(), do: table
  end

  # An index on a table born in this file builds inside the transaction - the table is
  # empty, so the build is instant and the file keeps its all-or-nothing shape.
  defp concurrent?(%{op: :create_index} = op, born_here) do
    op.table not in born_here
  end

  defp concurrent?(_op, _born_here), do: false

  # The renamed member's derivations live under its new name afterwards, so the pairing
  # follows the rename rather than the name.
  defp corresponding_source({:attribute, name}, %{op: :rename_attribute, from: name} = op) do
    {:attribute, op.to}
  end

  defp corresponding_source({:relationship, name}, %{op: :rename_relationship, from: name} = op) do
    {:relationship, op.to}
  end

  defp corresponding_source(source, _op), do: source

  defp declared?(%{source: {kind, _name}}) when kind in [:attribute, :relationship], do: true

  defp declared?(_column), do: false

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
  # value of the grant store's role type, an entity rename moves one of its resource_type
  # (the value IS the table name), and an enum value rename moves one of the attribute's
  # own type. Rows follow the label in every case - no rewrite.
  defp enum_value_ops(%{op: :rename_entity} = op, pre_mapping, post_mapping) do
    relabel_ops(
      pre_mapping,
      post_mapping,
      :resource_type,
      Map.fetch!(pre_mapping, op.from).table,
      Map.fetch!(post_mapping, op.to).table
    )
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
  # another by resource_type, not by the enum value, which is deduplicated across the
  # model. So renaming one entity's role relabels every type's grants unless the rows are
  # remapped within that resource_type - and the value has to survive for the others.
  defp enum_value_ops(%{op: :rename_role, entity: entity_type} = op, pre_mapping, post_mapping) do
    from = Codec.encode(op.from, :enum)
    to = Codec.encode(op.to, :enum)

    if from in role_values(post_mapping) do
      scoped_role_rebuild_ops(post_mapping, entity_type, from, to)
    else
      relabel_ops(pre_mapping, post_mapping, :role, from, to)
    end
  end

  # A global role's value is its module name, which no entity role can collide with, so
  # renaming one always moves a value nothing else holds.
  defp enum_value_ops(%{op: :rename_role} = op, pre_mapping, post_mapping) do
    relabel_ops(
      pre_mapping,
      post_mapping,
      :role,
      Codec.encode(op.from, :enum),
      Codec.encode(op.to, :enum)
    )
  end

  defp enum_value_ops(_op, _pre_mapping, _post_mapping), do: []

  # Every derived name of the entity, paired before and after the rename - whatever
  # differs is renamed. The table goes first, so the constraint and index renames that
  # follow already name it as it now stands.
  defp physical_renames(pre_entity, post_entity, op) do
    table = post_entity.table

    table_ops = name_op(:rename_table, nil, pre_entity.table, post_entity.table)

    pk_ops =
      name_op(:rename_constraint, table, pre_entity.pk_constraint, post_entity.pk_constraint)

    # Only declared columns pair by source: the system ones share the :system source and
    # carry fixed names, so they never take part in a rename.
    column_ops =
      Enum.flat_map(pre_entity.columns, fn pre_column ->
        source = corresponding_source(pre_column.source, op)
        post_column = Enum.find(post_entity.columns, &(&1.source == source))

        if declared?(pre_column) and post_column do
          column_renames(pre_column, post_column, table)
        else
          []
        end
      end)

    join_table_ops =
      Enum.flat_map(pre_entity.join_tables, fn pre_join ->
        {:relationship, name} = corresponding_source({:relationship, pre_join.relationship}, op)
        post_join = Enum.find(post_entity.join_tables, &(&1.relationship == name))

        if post_join, do: join_table_renames(pre_join, post_join), else: []
      end)

    table_ops ++ pk_ops ++ column_ops ++ join_table_ops
  end

  defp column_renames(pre_column, post_column, table) do
    name_op(:rename_column, table, pre_column.name, post_column.name) ++
      name_op(:rename_constraint, table, pre_column.fk_constraint, post_column.fk_constraint) ++
      name_op(:rename_index, nil, pre_column.fk_index, post_column.fk_index) ++
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
      ) ++
      name_op(:rename_index, nil, pre_join.reverse_index, post_join.reverse_index)
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
  # still declare it, the new one arrives beside it, and only the rows of this type's
  # resource follow. A fresh type also sidesteps PostgreSQL refusing to use a value added
  # by ALTER TYPE in the transaction that added it.
  defp scoped_role_rebuild_ops(mapping, entity_type, from, to) do
    grant_entry = Map.fetch!(mapping, RoleGrant)
    role_column = role_grant_column(grant_entry, :role)
    resource_type_column = role_grant_column(grant_entry, :resource_type)

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
            scope: {resource_type_column.name, Map.fetch!(mapping, entity_type).table}
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

  defp render_plain_chunk(chunk, model) do
    next_model = Model.fold(model, chunk)

    physical_ops =
      model
      |> term()
      |> Schema.diff(term(next_model))
      |> attach_backfills(chunk)
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
        |> Schema.diff(term(post_model))
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
      |> Schema.diff(term(post_model))

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

        if post_entity, do: physical_renames(pre_entity, post_entity, op), else: []
      end)

    entity_ops ++ enum_value_ops(op, pre_mapping, post_mapping)
  end

  defp term(model) do
    model
    |> Mapper.derive_from_model!()
    |> Schema.from_mapping()
  end
end
