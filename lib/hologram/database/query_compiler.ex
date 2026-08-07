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

  Cardinality shapes the statement: `:set` selects the mapped columns with ordering
  and view bounds, `:one` selects with `LIMIT 1` under the query's total order (a
  zero limit stays zero), and `:count` selects `count(*)` - over a capped subquery
  when view bounds are set, since a counting query counts what it evaluates to.

  Nil is a regular value for equality and membership on both execution tiers:
  inequality matches missing values (`!=` widens with `OR IS NULL` on optional
  attributes), membership lists may hold nil (compiled into the `IS [NOT] NULL`
  branch alongside the stripped array), and negated membership without nil matches
  missing values. Ordering comparisons match actual values only. Param slots never
  bind nil at runtime - a sometimes-nil variable branches into an explicit nil
  predicate in code.
  """
  @spec compile(%{atom => any}, %{module => %{atom => any}}) :: %{atom => any}
  def compile(term, mapping) do
    entity_mapping = Map.fetch!(mapping, term.entity)

    {where_sql, params} = where_clause(term.filter, entity_mapping)
    order_sql = order_clause(term.order_by, entity_mapping)

    %{params: params, sql: statement(term, entity_mapping, where_sql, order_sql)}
  end

  defp bind_slot({:param, param_name}, column, reversed_params) do
    {"$#{length(reversed_params) + 1}", [{:param, param_name, column.type} | reversed_params]}
  end

  defp bind_slot(literal, column, reversed_params) do
    encoded_value = Codec.encode(literal, column.type)

    {"$#{length(reversed_params) + 1}", [{:value, encoded_value} | reversed_params]}
  end

  defp bounds_clause(term) do
    limit_sql = if term.limit, do: " LIMIT #{term.limit}", else: ""
    offset_sql = if term.offset, do: " OFFSET #{term.offset}", else: ""

    limit_sql <> offset_sql
  end

  defp column_list(entity_mapping) do
    Enum.map_join(entity_mapping.columns, ", ", &Mapper.quote_identifier(&1.name))
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

  defp condition({name, :in, values}, entity_mapping, reversed_params) when is_list(values) do
    column = fetch_column!(entity_mapping, name)
    quoted_name = Mapper.quote_identifier(column.name)

    case Enum.reject(values, &is_nil/1) do
      [] ->
        {"#{quoted_name} IS NULL", reversed_params}

      ^values ->
        {placeholder, new_params} = membership_slot(values, column, reversed_params)

        {"#{quoted_name} = ANY(#{placeholder})", new_params}

      stripped_values ->
        {placeholder, new_params} = membership_slot(stripped_values, column, reversed_params)

        {null_inclusive("#{quoted_name} = ANY(#{placeholder})", column), new_params}
    end
  end

  defp condition({name, :in, operand}, entity_mapping, reversed_params) do
    column = fetch_column!(entity_mapping, name)
    {placeholder, new_params} = membership_slot(operand, column, reversed_params)

    {"#{Mapper.quote_identifier(column.name)} = ANY(#{placeholder})", new_params}
  end

  defp condition({name, :not_in, values}, entity_mapping, reversed_params)
       when is_list(values) do
    column = fetch_column!(entity_mapping, name)
    quoted_name = Mapper.quote_identifier(column.name)

    case Enum.reject(values, &is_nil/1) do
      [] ->
        {"#{quoted_name} IS NOT NULL", reversed_params}

      ^values ->
        {placeholder, new_params} = membership_slot(values, column, reversed_params)

        {null_inclusive("#{quoted_name} != ALL(#{placeholder})", column), new_params}

      stripped_values ->
        {placeholder, new_params} = membership_slot(stripped_values, column, reversed_params)

        condition_sql = "#{quoted_name} != ALL(#{placeholder})"

        {maybe_require_value(condition_sql, quoted_name, column), new_params}
    end
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

  defp direction_sql(:asc), do: "ASC"
  defp direction_sql(:desc), do: "DESC"

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

  defp maybe_require_value(condition_sql, quoted_name, %{null: true}) do
    "(#{condition_sql} AND #{quoted_name} IS NOT NULL)"
  end

  defp maybe_require_value(condition_sql, _quoted_name, _column), do: condition_sql

  defp null_inclusive(condition_sql, %{null: true} = column) do
    "(#{condition_sql} OR #{Mapper.quote_identifier(column.name)} IS NULL)"
  end

  defp null_inclusive(condition_sql, _column), do: condition_sql

  defp order_clause([], _entity_mapping), do: ""

  defp order_clause(entries, entity_mapping) do
    rendered_entries =
      Enum.map_join(entries, ", ", fn {name, direction} ->
        "#{quoted_column_name(entity_mapping, name)} #{direction_sql(direction)}"
      end)

    " ORDER BY " <> rendered_entries
  end

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(table)}"
  end

  defp quoted_column_name(entity_mapping, name) do
    entity_mapping
    |> fetch_column!(name)
    |> Map.fetch!(:name)
    |> Mapper.quote_identifier()
  end

  defp statement(%{cardinality: :count} = term, entity_mapping, where_sql, _order_sql) do
    from_sql = "FROM #{qualified_table(entity_mapping.table)}#{where_sql}"
    bounds_sql = bounds_clause(term)

    if bounds_sql == "" do
      "SELECT count(*) #{from_sql}"
    else
      ~s|SELECT count(*) FROM (SELECT 1 #{from_sql}#{bounds_sql}) AS "sub"|
    end
  end

  defp statement(%{cardinality: :one} = term, entity_mapping, where_sql, order_sql) do
    effective_limit = if term.limit == 0, do: 0, else: 1
    offset_sql = if term.offset, do: " OFFSET #{term.offset}", else: ""

    "SELECT #{column_list(entity_mapping)} FROM #{qualified_table(entity_mapping.table)}" <>
      where_sql <> order_sql <> " LIMIT #{effective_limit}" <> offset_sql
  end

  defp statement(term, entity_mapping, where_sql, order_sql) do
    "SELECT #{column_list(entity_mapping)} FROM #{qualified_table(entity_mapping.table)}" <>
      where_sql <> order_sql <> bounds_clause(term)
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
