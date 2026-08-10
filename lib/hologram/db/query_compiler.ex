defmodule Hologram.DB.QueryCompiler do
  @moduledoc false

  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper

  @data_schema "hologram_data"

  @doc """
  Compiles the given normalized query term into a SQL statement using the given
  physical name mapping.

  Returns a map with :sql (the statement string, identifiers quoted and
  schema-qualified) and :params (the bind slots in placeholder order). Every filter
  value binds as a placeholder - literal values are Codec-encoded at compilation into
  `{:value, encoded}` slots (membership lists encode element-wise into one array
  slot), param leaves become `{:param, name, type}` slots carrying the attribute's
  logical type for runtime encoding (`{:list, type}` for membership operands). A
  membership list holding param elements binds one slot per element inside a cast
  ARRAY constructor instead - each element param is a scalar slot. Nil
  equality compiles to `IS NULL` and nil inequality to `IS NOT NULL`, with no bind
  slot. Column selection follows the mapping's physical column order.

  Cardinality shapes the statement: `:set` selects the mapped columns with ordering
  and view bounds, `:one` selects with `LIMIT 1` under the query's total order (a
  zero limit stays zero), and `:count` selects `count(*)` - over a capped subquery
  when view bounds are set, since a counting query counts what it evaluates to.
  Counting queries carry no includes - an embedded entity cannot change the count.

  Includes compile into correlated jsonb subselects - one per included relationship,
  in sorted name order, each aliased distinctly (self-referencing relationships stay
  unambiguous - the root table is addressed by name). The jsonb keys are the target's
  physical column names in mapping order. A to-one subselect is NULL when the
  reference is. A to-many subselect aggregates the related set through its join table
  into a jsonb array (empty set = empty array), applying the sub-term's filter,
  ordering, and view bounds inside the aggregation - include param slots follow the
  root's in placeholder order.

  A compiled policy composes into the statement when one is given: its rules render as an
  OR group ANDed after the authored filter, so a row must satisfy the query and at least one
  rule. Rules are conjunctions of the same predicate triples the authored filter uses, and an
  unconditional rule (no conditions) satisfies the group on its own, which drops the group
  from the statement. An empty rule list denies everything (`FALSE`) - default deny. The
  actor leaf binds ONE reserved slot allocated after the authored and include params and
  reused by every actor reference in the policy, so the caller binds the session's user once.

  Nil is a regular value for equality and membership on both execution tiers:
  inequality matches missing values (`!=` widens with `OR IS NULL` on optional
  attributes), membership lists may hold nil (compiled into the `IS [NOT] NULL`
  branch alongside the stripped array), and negated membership without nil matches
  missing values. Ordering comparisons match actual values only. Param slots never
  bind nil at runtime - a sometimes-nil variable branches into an explicit nil
  predicate in code.
  """
  @spec compile(%{atom => any}, %{module => %{atom => any}}, list(map) | nil) :: %{atom => any}
  def compile(term, mapping, rules \\ nil) do
    entity_mapping = Map.fetch!(mapping, term.entity)

    {authored_conditions, authored_params} = conditions(term.filter, entity_mapping, [])

    {include_sql, params_after_includes} =
      include_selects(term, entity_mapping, mapping, authored_params)

    {policy_conditions, all_reversed_params} =
      policy_conditions(rules, entity_mapping, params_after_includes)

    where_sql = where_clause(authored_conditions ++ policy_conditions)
    order_sql = order_clause(term.order_by, entity_mapping)
    sql = statement(term, entity_mapping, where_sql, order_sql, include_sql)

    %{params: Enum.reverse(all_reversed_params), sql: sql}
  end

  defp aggregate_order([], _target_mapping, _quoted_alias), do: ""

  defp aggregate_order(entries, target_mapping, quoted_alias) do
    rendered_entries =
      Enum.map_join(entries, ", ", fn {name, direction} ->
        target_mapping
        |> order_column_names(name)
        |> Enum.map_join(", ", fn column_name ->
          "#{quoted_alias}.#{Mapper.quote_identifier(column_name)} #{direction_sql(direction)}"
        end)
      end)

    " ORDER BY " <> rendered_entries
  end

  # Bind slots inside an ARRAY constructor carry no type context of their own -
  # without the cast Postgres resolves them to text.
  defp array_type(%{type: :enum, sql_type: sql_type}) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(sql_type)}[]"
  end

  defp array_type(%{sql_type: sql_type}), do: "#{sql_type}[]"

  # The actor leaf binds one reserved slot for the whole statement - every reference to it
  # reuses that placeholder, so the caller binds the session's user exactly once.
  defp bind_slot({:actor}, _column, reversed_params) do
    case Enum.find_index(reversed_params, &(&1 == :actor)) do
      nil ->
        {"$#{length(reversed_params) + 1}", [:actor | reversed_params]}

      reversed_index ->
        {"$#{length(reversed_params) - reversed_index}", reversed_params}
    end
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

  defp policy_conditions(nil, _entity_mapping, reversed_params), do: {[], reversed_params}

  defp policy_conditions([], _entity_mapping, reversed_params), do: {["FALSE"], reversed_params}

  defp policy_conditions(rules, entity_mapping, reversed_params) do
    {rendered_rules, new_params} =
      Enum.map_reduce(rules, reversed_params, fn rule, acc_params ->
        rule_condition(rule, entity_mapping, acc_params)
      end)

    if Enum.any?(rendered_rules, &(&1 == :unconditional)) do
      {[], new_params}
    else
      {[group_condition(rendered_rules)], new_params}
    end
  end

  defp group_condition([rule_sql]), do: rule_sql

  defp group_condition(rule_sqls) do
    "(" <> Enum.map_join(rule_sqls, " OR ", &"(#{&1})") <> ")"
  end

  # TODO: grant references and delegations render as a denial until the grant store and
  # delegation composition land - an under-approximation, so no row is shown that a rule
  # does not grant.
  defp requirement_conditions(%{to: nil, via: nil}), do: []

  defp requirement_conditions(_rule), do: ["FALSE"]

  defp rule_condition(rule, entity_mapping, reversed_params) do
    {predicate_conditions, new_params} =
      conditions(rule.predicates, entity_mapping, reversed_params)

    case predicate_conditions ++ requirement_conditions(rule) do
      [] -> {:unconditional, new_params}
      rule_conditions -> {Enum.join(rule_conditions, " AND "), new_params}
    end
  end

  defp conditions(triples, entity_mapping, reversed_params) do
    Enum.map_reduce(triples, reversed_params, fn triple, acc_params ->
      condition(triple, entity_mapping, acc_params)
    end)
  end

  defp direction_sql(:asc), do: "ASC"
  defp direction_sql(:desc), do: "DESC"

  defp fetch_column!(%{columns: columns}, name) do
    column_name = Atom.to_string(name)

    Enum.find(columns, fn column ->
      case column.source do
        {:attribute, attribute_name} -> attribute_name == name
        {:relationship, relationship_name} -> "#{relationship_name}_id" == column_name
        :system -> column.name == column_name
        _other_source -> false
      end
    end)
  end

  defp membership_slot({:param, param_name}, column, reversed_params) do
    {"$#{length(reversed_params) + 1}",
     [{:param, param_name, {:list, column.type}} | reversed_params]}
  end

  # A list holding param elements binds one slot per element inside an ARRAY
  # constructor - each element param is a scalar slot of the attribute's type.
  defp membership_slot(values, column, reversed_params) do
    if Enum.any?(values, &match?({:param, _param_name}, &1)) do
      {reversed_placeholders, new_params} =
        Enum.reduce(values, {[], reversed_params}, fn value, {acc_placeholders, acc_params} ->
          {placeholder, next_params} = bind_slot(value, column, acc_params)

          {[placeholder | acc_placeholders], next_params}
        end)

      placeholders =
        reversed_placeholders
        |> Enum.reverse()
        |> Enum.join(", ")

      {"ARRAY[#{placeholders}]::#{array_type(column)}", new_params}
    else
      encoded_values = Enum.map(values, &Codec.encode(&1, column.type))

      {"$#{length(reversed_params) + 1}", [{:value, encoded_values} | reversed_params]}
    end
  end

  defp include_expression({name, sub_term}, parent_mapping, mapping, parent_prefix, acc) do
    join_table = Enum.find(parent_mapping.join_tables, &(&1.relationship == name))

    if join_table do
      to_many_include_expression(sub_term, join_table, mapping, parent_prefix, acc)
    else
      to_one_include_expression(name, sub_term, parent_mapping, mapping, parent_prefix, acc)
    end
  end

  defp include_pairs(term, target_mapping, mapping, quoted_alias, acc) do
    {fragments, new_acc} =
      term.include
      |> Enum.sort_by(fn {entry_name, _sub_term} -> entry_name end)
      |> Enum.map_reduce(acc, fn {entry_name, _sub_term} = entry, inner_acc ->
        {expression, next_acc} =
          include_expression(entry, target_mapping, mapping, quoted_alias, inner_acc)

        {", '#{entry_name}', #{expression}", next_acc}
      end)

    {Enum.join(fragments, ""), new_acc}
  end

  defp include_selects(%{cardinality: :count}, _entity_mapping, _mapping, reversed_params) do
    {"", reversed_params}
  end

  defp include_selects(term, entity_mapping, mapping, reversed_params) do
    quoted_prefix = Mapper.quote_identifier(entity_mapping.table)

    {fragments, {new_params, _next_index}} =
      term.include
      |> Enum.sort_by(fn {name, _sub_term} -> name end)
      |> Enum.map_reduce({reversed_params, 1}, fn {name, _sub_term} = entry, acc ->
        {expression, new_acc} =
          include_expression(entry, entity_mapping, mapping, quoted_prefix, acc)

        {", #{expression} AS #{Mapper.quote_identifier(Atom.to_string(name))}", new_acc}
      end)

    {Enum.join(fragments, ""), new_params}
  end

  defp jsonb_pairs(target_mapping, quoted_alias) do
    Enum.map_join(target_mapping.columns, ", ", fn column ->
      "'#{column.name}', #{quoted_alias}.#{Mapper.quote_identifier(column.name)}"
    end)
  end

  defp maybe_require_value(condition_sql, quoted_name, %{null: true}) do
    "(#{condition_sql} AND #{quoted_name} IS NOT NULL)"
  end

  defp maybe_require_value(condition_sql, _quoted_name, _column), do: condition_sql

  defp null_inclusive(condition_sql, %{null: true} = column) do
    "(#{condition_sql} OR #{Mapper.quote_identifier(column.name)} IS NULL)"
  end

  defp null_inclusive(condition_sql, _column), do: condition_sql

  # A :string ordering whose mapping carries a `<attribute>_$sort` companion
  # orders by the companion first and the original column right after it (ties
  # past the key cap break on the full original bytes), both in the entry's
  # direction. Without a companion the raw column orders alone.
  defp order_clause([], _entity_mapping), do: ""

  defp order_clause(entries, entity_mapping) do
    rendered_entries =
      Enum.map_join(entries, ", ", fn {name, direction} ->
        entity_mapping
        |> order_column_names(name)
        |> Enum.map_join(", ", fn column_name ->
          "#{Mapper.quote_identifier(column_name)} #{direction_sql(direction)}"
        end)
      end)

    " ORDER BY " <> rendered_entries
  end

  defp order_column_names(entity_mapping, name) do
    column = fetch_column!(entity_mapping, name)

    companion =
      Enum.find(entity_mapping.columns, &(&1.source == {:sort_key, name}))

    if companion do
      [companion.name, column.name]
    else
      [column.name]
    end
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

  defp statement(
         %{cardinality: :count} = term,
         entity_mapping,
         where_sql,
         _order_sql,
         _include_sql
       ) do
    from_sql = "FROM #{qualified_table(entity_mapping.table)}#{where_sql}"
    bounds_sql = bounds_clause(term)

    if bounds_sql == "" do
      "SELECT count(*) #{from_sql}"
    else
      ~s|SELECT count(*) FROM (SELECT 1 #{from_sql}#{bounds_sql}) AS "sub"|
    end
  end

  defp statement(%{cardinality: :one} = term, entity_mapping, where_sql, order_sql, include_sql) do
    effective_limit = if term.limit == 0, do: 0, else: 1
    offset_sql = if term.offset, do: " OFFSET #{term.offset}", else: ""

    "SELECT #{column_list(entity_mapping)}#{include_sql} " <>
      "FROM #{qualified_table(entity_mapping.table)}" <>
      where_sql <> order_sql <> " LIMIT #{effective_limit}" <> offset_sql
  end

  defp statement(term, entity_mapping, where_sql, order_sql, include_sql) do
    "SELECT #{column_list(entity_mapping)}#{include_sql} " <>
      "FROM #{qualified_table(entity_mapping.table)}" <>
      where_sql <> order_sql <> bounds_clause(term)
  end

  defp to_many_include_expression(
         sub_term,
         join_table,
         mapping,
         parent_prefix,
         {reversed_params, index}
       ) do
    target_mapping = Map.fetch!(mapping, sub_term.entity)
    quoted_wrapper = Mapper.quote_identifier("i#{index}")
    quoted_join = Mapper.quote_identifier("j#{index}")
    quoted_target = Mapper.quote_identifier("t#{index}")

    {conditions, filtered_params} = conditions(sub_term.filter, target_mapping, reversed_params)
    filter_sql = Enum.map_join(conditions, "", &(" AND " <> &1))

    {nested_pairs, new_acc} =
      include_pairs(
        sub_term,
        target_mapping,
        mapping,
        quoted_wrapper,
        {filtered_params, index + 1}
      )

    # The edge scan is a nested subselect (not a join) so that only the target
    # table is in scope where the sub-term's filter and ordering render their
    # unqualified identifiers - a join would make target columns named like the
    # join-table columns (source_id/target_id) ambiguous.
    inner_sql =
      "SELECT #{quoted_target}.* " <>
        "FROM #{qualified_table(target_mapping.table)} AS #{quoted_target} " <>
        ~s|WHERE #{quoted_target}."id" IN | <>
        ~s|(SELECT #{quoted_join}."target_id" | <>
        "FROM #{qualified_table(join_table.name)} AS #{quoted_join} " <>
        ~s|WHERE #{quoted_join}."source_id" = #{parent_prefix}."id")| <>
        filter_sql <>
        order_clause(sub_term.order_by, target_mapping) <>
        bounds_clause(sub_term)

    expression =
      "(SELECT COALESCE(jsonb_agg(jsonb_build_object(#{jsonb_pairs(target_mapping, quoted_wrapper)}#{nested_pairs})" <>
        aggregate_order(sub_term.order_by, target_mapping, quoted_wrapper) <>
        "), '[]'::jsonb) FROM (#{inner_sql}) AS #{quoted_wrapper})"

    {expression, new_acc}
  end

  defp to_one_include_expression(
         name,
         sub_term,
         parent_mapping,
         mapping,
         parent_prefix,
         {reversed_params, index}
       ) do
    reference_column =
      Enum.find(parent_mapping.columns, &(&1.source == {:relationship, name}))

    target_mapping = Map.fetch!(mapping, sub_term.entity)
    quoted_alias = Mapper.quote_identifier("i#{index}")

    {nested_pairs, new_acc} =
      include_pairs(sub_term, target_mapping, mapping, quoted_alias, {reversed_params, index + 1})

    expression =
      "(SELECT jsonb_build_object(#{jsonb_pairs(target_mapping, quoted_alias)}#{nested_pairs}) " <>
        "FROM #{qualified_table(target_mapping.table)} AS #{quoted_alias} " <>
        ~s|WHERE #{quoted_alias}."id" = #{parent_prefix}.#{Mapper.quote_identifier(reference_column.name)})|

    {expression, new_acc}
  end

  defp where_clause([]), do: ""

  defp where_clause(conditions), do: " WHERE " <> Enum.join(conditions, " AND ")
end
