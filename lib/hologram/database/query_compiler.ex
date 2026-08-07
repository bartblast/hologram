defmodule Hologram.Database.QueryCompiler do
  @moduledoc false

  alias Hologram.Database.Codec
  alias Hologram.Database.Mapper

  @data_schema "hologram_data"

  @doc """
  Compiles the given normalized query term into a SQL statement using the given
  physical name mapping.

  Returns a map with :sql (the statement string, identifiers quoted and
  schema-qualified) and :params (the bind slots in placeholder order). Every filter
  value binds as a placeholder - literal values are Codec-encoded at compilation into
  `{:value, encoded}` slots (membership lists encode element-wise into one array
  slot), param leaves become `{:param, name, type}` slots carrying the attribute's
  logical type for runtime encoding (`{:list, type}` for membership operands). Nil
  equality compiles to `IS NULL` and nil inequality to `IS NOT NULL`, with no bind
  slot. Column selection follows the mapping's physical column order.

  NULL semantics on optional attributes are pinned to agree across execution tiers:
  inequality and negated membership are null-INCLUSIVE (`nil != x` is true on the
  client, so the SQL widens with `OR IS NULL`), while membership and ordering
  comparisons are null-EXCLUSIVE (a NULL is in no membership list, and ordering
  against a missing value matches nothing).
  """
  @spec compile(%{atom => any}, %{module => %{atom => any}}) :: %{atom => any}
  def compile(term, mapping) do
    entity_mapping = Map.fetch!(mapping, term.entity)

    column_list = Enum.map_join(entity_mapping.columns, ", ", &Mapper.quote_identifier(&1.name))

    {where_sql, params} = where_clause(term.filter, entity_mapping)

    %{
      params: params,
      sql: "SELECT #{column_list} FROM #{qualified_table(entity_mapping.table)}#{where_sql}"
    }
  end

  defp bind_slot({:param, param_name}, column, reversed_params) do
    {"$#{length(reversed_params) + 1}", [{:param, param_name, column.type} | reversed_params]}
  end

  defp bind_slot(literal, column, reversed_params) do
    encoded_value = Codec.encode(literal, column.type)

    {"$#{length(reversed_params) + 1}", [{:value, encoded_value} | reversed_params]}
  end

  defp condition({name, :==, nil}, entity_mapping, reversed_params) do
    quoted_name = quoted_column_name(entity_mapping, name)

    {"#{quoted_name} IS NULL", reversed_params}
  end

  defp condition({name, :==, value}, entity_mapping, reversed_params) do
    column = fetch_column!(entity_mapping, name)
    {placeholder, new_params} = bind_slot(value, column, reversed_params)

    {"#{Mapper.quote_identifier(column.name)} = #{placeholder}", new_params}
  end

  defp condition({name, :!=, nil}, entity_mapping, reversed_params) do
    quoted_name = quoted_column_name(entity_mapping, name)

    {"#{quoted_name} IS NOT NULL", reversed_params}
  end

  defp condition({name, :!=, value}, entity_mapping, reversed_params) do
    column = fetch_column!(entity_mapping, name)
    {placeholder, new_params} = bind_slot(value, column, reversed_params)

    condition_sql = "#{Mapper.quote_identifier(column.name)} != #{placeholder}"

    {null_inclusive(condition_sql, column), new_params}
  end

  defp condition({name, :in, operand}, entity_mapping, reversed_params) do
    column = fetch_column!(entity_mapping, name)
    {placeholder, new_params} = membership_slot(operand, column, reversed_params)

    {"#{Mapper.quote_identifier(column.name)} = ANY(#{placeholder})", new_params}
  end

  defp condition({name, :not_in, operand}, entity_mapping, reversed_params) do
    column = fetch_column!(entity_mapping, name)
    {placeholder, new_params} = membership_slot(operand, column, reversed_params)

    condition_sql = "#{Mapper.quote_identifier(column.name)} != ALL(#{placeholder})"

    {null_inclusive(condition_sql, column), new_params}
  end

  defp condition({name, operator, value}, entity_mapping, reversed_params) do
    column = fetch_column!(entity_mapping, name)
    {placeholder, new_params} = bind_slot(value, column, reversed_params)

    {"#{Mapper.quote_identifier(column.name)} #{operator} #{placeholder}", new_params}
  end

  defp fetch_column!(%{columns: columns}, name) do
    column_name = Atom.to_string(name)

    Enum.find(columns, fn column ->
      column.source == {:attribute, name} or
        (column.source == :system and column.name == column_name)
    end)
  end

  defp membership_slot({:param, param_name}, column, reversed_params) do
    {"$#{length(reversed_params) + 1}",
     [{:param, param_name, {:list, column.type}} | reversed_params]}
  end

  defp membership_slot(values, column, reversed_params) do
    encoded_values = Enum.map(values, &Codec.encode(&1, column.type))

    {"$#{length(reversed_params) + 1}", [{:value, encoded_values} | reversed_params]}
  end

  defp null_inclusive(condition_sql, %{null: true} = column) do
    "(#{condition_sql} OR #{Mapper.quote_identifier(column.name)} IS NULL)"
  end

  defp null_inclusive(condition_sql, _column), do: condition_sql

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(table)}"
  end

  defp quoted_column_name(entity_mapping, name) do
    entity_mapping
    |> fetch_column!(name)
    |> Map.fetch!(:name)
    |> Mapper.quote_identifier()
  end

  defp where_clause([], _entity_mapping), do: {"", []}

  defp where_clause(triples, entity_mapping) do
    {conditions, reversed_params} =
      Enum.map_reduce(triples, [], fn triple, acc_params ->
        condition(triple, entity_mapping, acc_params)
      end)

    {" WHERE " <> Enum.join(conditions, " AND "), Enum.reverse(reversed_params)}
  end
end
