defmodule Hologram.Migration.Renderer do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.DB.Schema
  alias Hologram.Entity.Model

  # Physical ops that reference objects rather than defining them, so they run once
  # everything they name exists - the file-scope form of 02b's phase order.
  @deferred_ops [:add_foreign_key, :create_index]

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
  @spec render(list(%{atom => any}), %{atom => map}) :: %{atom => any}
  def render(logical_ops, pre_model) do
    {physical_ops, post_model} =
      logical_ops
      |> Enum.chunk_by(&(&1.op in @rename_ops))
      |> Enum.reduce({[], pre_model}, fn chunk, {acc, model} ->
        {ops, next_model} = render_chunk(chunk, model)

        {acc ++ ops, next_model}
      end)

    ordered = order(physical_ops)
    born_here = born_here(ordered)
    {transactional, tail} = Enum.split_with(ordered, &(not concurrent?(&1, born_here)))

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
        {{Mapper.table_name(op.entity), Atom.to_string(op.name)}, value}
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
    rename_enum_value_ops(
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

  defp enum_value_ops(%{op: :rename_role} = op, _pre_mapping, post_mapping) do
    rename_enum_value_ops(
      post_mapping,
      :role,
      Codec.encode(op.from, :enum),
      Codec.encode(op.to, :enum)
    )
  end

  defp enum_value_ops(_op, _pre_mapping, _post_mapping), do: []

  # Foreign key drops run first and the referencing ops last, so an op never names an
  # object a later op in the same file creates.
  defp order(ops) do
    {fk_drops, rest} = Enum.split_with(ops, &(&1.op == :drop_foreign_key))
    {deferred, middle} = Enum.split_with(rest, &(&1.op in @deferred_ops))

    fk_drops ++ middle ++ deferred
  end

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

  defp render_chunk([%{op: kind} | _rest] = chunk, model) when kind in @rename_ops do
    Enum.reduce(chunk, {[], model}, fn op, {acc, current_model} ->
      next_model = Model.fold(current_model, [op])

      {acc ++ rename_ops_for(op, current_model, next_model), next_model}
    end)
  end

  defp render_chunk(chunk, model) do
    next_model = Model.fold(model, chunk)

    physical_ops =
      model
      |> term()
      |> Schema.diff(term(next_model))
      |> attach_backfills(chunk)

    {physical_ops, next_model}
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
