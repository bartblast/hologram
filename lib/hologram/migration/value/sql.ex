defmodule Hologram.Migration.Value.SQL do
  @moduledoc false

  # Renders a resolved backfill to an SQL expression over the row aliased "$r0", through a mapping
  # of the schema at the op. It has its own walk rather than the query compiler's because it reads
  # a point in a migration's history, not the compiled entity modules. What each word means comes
  # from Hologram.DB.WordSQL.

  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryCompiler
  alias Hologram.DB.WordSQL
  alias Hologram.Migration.Value.Resolver

  @plain_sql_types %{
    boolean: "boolean",
    date: "date",
    datetime: "timestamptz",
    float: "float8",
    integer: "int8",
    string: "text",
    time: "time",
    uuid: "uuid"
  }

  @doc """
  Returns the SQL expression of the given resolved backfill for the given target member of the
  given entity type, and the parameters it binds, in order. An enum of another attribute is cast
  to the target's type, since each enum attribute has a PostgreSQL type of its own.
  """
  @spec render(
          %{term: Resolver.resolved(), type: Resolver.type()},
          module,
          %{module => %{atom => any}},
          Resolver.target()
        ) :: {String.t(), list}
  def render(%{term: term, type: type}, entity_type, mapping, target) do
    scope = %{depth: 0, entity: entity_type, mapping: mapping}

    {sql, reversed_params} = term_sql(term, scope, [])

    {cast_to_target(sql, type, entity_type, mapping, target), Enum.reverse(reversed_params)}
  end

  defp attribute_column!(mapping, owner, name) do
    mapping
    |> Map.fetch!(owner)
    |> Map.fetch!(:columns)
    |> Enum.find(&(&1.source == {:attribute, name}))
  end

  defp cast_to_target(sql, {:enum, owner, name, _values}, entity_type, mapping, %{
         kind: :attribute,
         name: target_name,
         type: :enum
       })
       when {owner, name} != {entity_type, target_name} do
    "(#{sql})::text::#{enum_sql_type(mapping, entity_type, target_name)}"
  end

  defp cast_to_target(sql, _type, _entity_type, _mapping, _target), do: sql

  defp column_sql(scope, column) do
    "#{row_alias(scope)}.#{Mapper.quote_identifier(column.name)}"
  end

  defp encode_type({:enum, _owner, _name, _values}), do: :enum

  defp encode_type({:reference, _target}), do: :uuid

  defp encode_type(type), do: type

  defp enum_sql_type(mapping, owner, name) do
    column = attribute_column!(mapping, owner, name)

    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(column.sql_type)}"
  end

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(table)}"
  end

  defp related_entity!(mapping, table) do
    {entity_type, _entry} = Enum.find(mapping, fn {_type, entry} -> entry.table == table end)

    entity_type
  end

  defp row_alias(%{depth: depth}), do: Mapper.quote_identifier("$r#{depth}")

  defp slot(value, type, scope, reversed_params) do
    encoded = Codec.encode(value, encode_type(type))
    number = length(reversed_params) + 1

    {"$#{number}::#{sql_type(type, scope.mapping)}", [encoded | reversed_params]}
  end

  defp sql_type({:enum, owner, name, _values}, mapping), do: enum_sql_type(mapping, owner, name)

  defp sql_type({:reference, _target}, _mapping), do: "uuid"

  defp sql_type(type, _mapping), do: Map.fetch!(@plain_sql_types, type)

  defp term_sql({:value, value, type}, scope, reversed_params) do
    slot(value, type, scope, reversed_params)
  end

  defp term_sql({:name, [name], _type}, scope, reversed_params) do
    entry = Map.fetch!(scope.mapping, scope.entity)

    {column_sql(scope, QueryCompiler.name_column(entry, name)), reversed_params}
  end

  # One scalar subquery per hop, each with an alias of its own, so a self-relationship reads
  # another row rather than itself. A nil reference finds no row, which reads as NULL.
  defp term_sql({:name, [hop | rest], type}, scope, reversed_params) do
    entry = Map.fetch!(scope.mapping, scope.entity)
    reference = Enum.find(entry.columns, &(&1.source == {:relationship, hop}))
    target_entity = related_entity!(scope.mapping, reference.references)
    inner_scope = %{scope | depth: scope.depth + 1, entity: target_entity}

    {inner_sql, new_params} = term_sql({:name, rest, type}, inner_scope, reversed_params)

    target_table = scope.mapping[target_entity].table

    sql =
      "(SELECT #{inner_sql} FROM #{qualified_table(target_table)} AS #{row_alias(inner_scope)} " <>
        "WHERE #{row_alias(inner_scope)}.\"id\" = #{column_sql(scope, reference)})"

    {sql, new_params}
  end

  defp term_sql({:concat, operands}, scope, reversed_params) do
    {operand_sqls, new_params} = terms_sql(operands, scope, reversed_params)

    {WordSQL.concat(operand_sqls), new_params}
  end

  defp term_sql(
         {:at, {:split, text, {:value, separator, :string}}, {:value, position, :integer}},
         scope,
         reversed_params
       ) do
    {text_sql, params_after_text} = term_sql(text, scope, reversed_params)
    {separator_sql, new_params} = slot(separator, :string, scope, params_after_text)

    {WordSQL.at_split(text_sql, separator_sql, position), new_params}
  end

  defp term_sql({:coalesce, values}, scope, reversed_params) do
    {value_sqls, new_params} = terms_sql(values, scope, reversed_params)

    {WordSQL.coalesce(value_sqls), new_params}
  end

  defp terms_sql(terms, scope, reversed_params) do
    Enum.map_reduce(terms, reversed_params, &term_sql(&1, scope, &2))
  end
end
