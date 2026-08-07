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
  `{:value, encoded}` slots, param leaves become `{:param, name, type}` slots carrying
  the attribute's logical type for runtime encoding. Nil equality compiles to
  `IS NULL` with no bind slot. Column selection follows the mapping's physical
  column order.
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

  defp condition({name, :==, value}, entity_mapping, reversed_params) do
    column = fetch_column!(entity_mapping, name)
    quoted_name = Mapper.quote_identifier(column.name)
    placeholder = length(reversed_params) + 1

    case value do
      nil ->
        {"#{quoted_name} IS NULL", reversed_params}

      {:param, param_name} ->
        {"#{quoted_name} = $#{placeholder}",
         [{:param, param_name, column.type} | reversed_params]}

      literal ->
        encoded_value = Codec.encode(literal, column.type)

        {"#{quoted_name} = $#{placeholder}", [{:value, encoded_value} | reversed_params]}
    end
  end

  defp fetch_column!(%{columns: columns}, name) do
    column_name = Atom.to_string(name)

    Enum.find(columns, fn column ->
      column.source == {:attribute, name} or
        (column.source == :system and column.name == column_name)
    end)
  end

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(table)}"
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
