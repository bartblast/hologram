defmodule Hologram.DB.QueryCompiler do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.DB.SortKey
  alias Hologram.Policy
  alias Hologram.Query

  @data_schema "hologram_data"

  @doc """
  Compiles the given normalized query term into a SQL statement using the given
  physical name mapping.

  Returns a map with :sql (the statement string, identifiers quoted and
  schema-qualified) and :params (the bind slots in parameter order). Every filter
  value binds as a parameter - literal values are Codec-encoded at compilation into
  `{:value, encoded}` slots (membership lists encode element-wise into one array
  slot), placeholder leaves become `{:placeholder, name, type}` slots carrying the attribute's
  logical type for runtime encoding (`{:list, type}` for membership operands). A
  membership list holding placeholder elements binds one slot per element inside a cast
  ARRAY constructor instead - each element placeholder is a scalar slot. Nil
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
  root's in parameter order.

  A compiled policy composes into the statement when one is given: its rules render as an
  OR group ANDed after the authored filter, so a row must satisfy the query and at least one
  rule. Rules are conjunctions of the same predicate triples the authored filter uses, and an
  unconditional rule (no conditions) satisfies the group on its own, which drops the group
  from the statement. An empty rule list denies everything (`FALSE`) - default deny. The
  actor leaf binds ONE reserved slot allocated after the authored and include params and
  reused by every actor reference in the policy, so the caller binds the session's user once.

  Includes are policied too, at every nesting level: an include subquery ANDs the included
  type's :read policy - fixed at :read, since an include embeds rows regardless of the
  operation the statement's own policy carries - keyed on the include's alias rather than
  the target table name. A to-one embed the acting user cannot
  read is NULL, and rows they cannot read drop out of a to-many aggregate before its view
  bounds apply. Compiling without a policy leaves every level unfiltered - the trusted tier.

  Nil is a regular value for equality and membership on both execution tiers:
  inequality matches missing values (`!=` widens with `OR IS NULL` on optional
  attributes), membership lists may hold nil (compiled into the `IS [NOT] NULL`
  branch alongside the stripped array), and negated membership without nil matches
  missing values. Ordering comparisons match actual values only. Param slots never
  bind nil at runtime - a sometimes-nil variable branches into an explicit nil
  predicate in code.
  """
  @spec compile(Query.t(), %{module => %{atom => any}}, %{atom => any} | nil) ::
          %{atom => any}
  def compile(term, mapping, policy \\ nil) do
    entity_mapping = Map.fetch!(mapping, term.entity)

    {authored_conditions, authored_params} = conditions(term.filter, entity_mapping, [])

    {include_sql, params_after_includes} =
      include_selects(term, entity_mapping, mapping, policy, authored_params)

    {policy_conditions, all_reversed_params} =
      policy_conditions(
        policy,
        policy_context(term.entity, mapping, policy),
        params_after_includes
      )

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
  defp actor_gated?(rule) do
    rule.to != nil or
      Enum.any?(rule.predicates, fn {_name, _operator, value} -> value == {:actor} end)
  end

  # A rule referencing the actor cannot match without one, so an anonymous statement drops it
  # rather than binding a nil placeholder - at every nesting level, delegated policies included.
  defp applicable_rules(rules, %{anonymous?: true}), do: Enum.reject(rules, &actor_gated?/1)

  defp applicable_rules(rules, _context), do: rules

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

  defp bind_slot({:placeholder, placeholder_name}, column, reversed_params) do
    {"$#{length(reversed_params) + 1}",
     [{:placeholder, placeholder_name, column.type} | reversed_params]}
  end

  defp bind_slot(literal, column, reversed_params) do
    encoded_value = Codec.encode(literal, column.type)

    {"$#{length(reversed_params) + 1}", [{:value, encoded_value} | reversed_params]}
  end

  defp enum_list_slot(values, column, reversed_params) do
    encoded_values = Enum.map(values, &Codec.encode(&1, column.type))
    {placeholder, new_params} = bind_slot_value(encoded_values, reversed_params)

    {"#{placeholder}::#{array_type(column)}", new_params}
  end

  defp enum_type(%{sql_type: sql_type}) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(sql_type)}"
  end

  defp bind_slot_value(encoded_value, reversed_params) do
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

  # A string compares by the pair its ordering sorts by - the key carries the order and the value
  # settles what the key cannot - so a bound is a position in the list the attribute sorts into,
  # and the comparison agrees with ORDER BY by construction. Every other type compares by its
  # column alone.
  defp condition({name, operator, value}, entity_mapping, reversed_params) do
    column = fetch_column!(entity_mapping, name)

    case companion_column(entity_mapping, name) do
      nil ->
        {placeholder, new_params} = bind_slot(value, column, reversed_params)

        {"#{Mapper.quote_identifier(column.name)} #{operator} #{placeholder}", new_params}

      companion ->
        {key_slot, raw_slot, new_params} = sort_key_slots(value, reversed_params)

        quoted_pair =
          "(#{Mapper.quote_identifier(companion.name)}, #{Mapper.quote_identifier(column.name)})"

        {"#{quoted_pair} #{operator} (#{key_slot}, #{raw_slot})", new_params}
    end
  end

  defp relationship_target(entity_type, relationship_name) do
    {_name, target_type, _opts} =
      Enum.find(entity_type.__relationships__(), fn {name, _type, _opts} ->
        name == relationship_name
      end)

    target_type
  end

  defp reference_column(entity_mapping, relationship_name) do
    Enum.find(entity_mapping.columns, &(&1.source == {:relationship, relationship_name}))
  end

  defp reference_role_names({:global, role_modules}), do: role_modules

  defp reference_role_names({:own, role_names}), do: role_names

  defp reference_role_names({:type, _target_type, role_names}), do: role_names

  defp reference_role_names({:rel, _relationship_name, role_names}), do: role_names

  defp reference_role_names({:resource, _target_type, role_names}), do: role_names

  # The resource type enum's values ARE the entity type modules, so a type binds as its own enum
  # label - the same string the client compares a grant row against.
  defp entity_type_slot(entity_type, context, reversed_params) do
    column = grant_column(context, "entity_type")

    {placeholder, new_params} =
      bind_slot_value(Codec.encode_enum_value(entity_type), reversed_params)

    {"#{placeholder}::#{enum_type(column)}", new_params}
  end

  # The row prefix qualifies references to the row a policy is evaluated for. It is the entity's
  # table name at statement level, and the include's alias inside an include subquery - where the
  # table name would resolve to the outer row for a self-referencing relationship.
  defp policy_context(entity_type, mapping, policy, quoted_row_prefix \\ nil)

  defp policy_context(_entity_type, _mapping, nil, _quoted_row_prefix), do: nil

  defp policy_context(entity_type, mapping, %{operation: operation} = policy, quoted_row_prefix) do
    entity_mapping = Map.fetch!(mapping, entity_type)

    %{
      anonymous?: Map.get(policy, :anonymous?, false),
      entity_mapping: entity_mapping,
      entity_type: entity_type,
      mapping: mapping,
      operation: operation,
      row_prefix: quoted_row_prefix || Mapper.quote_identifier(entity_mapping.table)
    }
  end

  defp policy_conditions(nil, _context, reversed_params), do: {[], reversed_params}

  defp policy_conditions(%{rules: rules}, context, reversed_params) do
    rules
    |> applicable_rules(context)
    |> applicable_policy_conditions(context, reversed_params)
  end

  defp applicable_policy_conditions([], _context, reversed_params),
    do: {["FALSE"], reversed_params}

  defp applicable_policy_conditions(rules, context, reversed_params) do
    {rendered_rules, new_params} =
      Enum.map_reduce(rules, reversed_params, fn rule, acc_params ->
        rule_condition(rule, context, acc_params)
      end)

    if Enum.any?(rendered_rules, &(&1 == :unconditional)) do
      # Dropping the group drops its placeholders, so the slots its rules bound go with it -
      # a placeholder the statement doesn't carry fails the bind.
      {[], reversed_params}
    else
      {[group_condition(rendered_rules)], new_params}
    end
  end

  defp grant_column(context, name) do
    context.mapping
    |> Map.fetch!(RoleGrant)
    |> Map.fetch!(:columns)
    |> Enum.find(&(&1.name == name))
  end

  # Enum values bind as placeholders cast to their column type, so the lookup keeps using the grant
  # store's unique index - the same shape the in-memory grant lookups use.
  defp grant_exists_condition(reference, context, reversed_params) do
    role_names = reference_role_names(reference)

    {actor_placeholder, params_after_actor} =
      bind_slot({:actor}, grant_column(context, "user_id"), reversed_params)

    {role_placeholder, params_after_roles} =
      enum_list_slot(role_names, grant_column(context, "role"), params_after_actor)

    {scope_sql, new_params} = grant_scope_sql(reference, context, params_after_roles)

    condition =
      ~s|EXISTS (SELECT 1 FROM #{grant_table(context)} AS "rg" | <>
        ~s|WHERE "rg"."user_id" = #{actor_placeholder} | <>
        ~s|AND "rg"."role" = ANY(#{role_placeholder}) AND #{scope_sql})|

    {condition, new_params}
  end

  # A global role is held without a resource, so the row shape has both resource columns nil -
  # the lookup needs no correlation with the queried row.
  defp grant_scope_sql({:global, _role_modules}, _context, reversed_params) do
    {~s|"rg"."entity_type" IS NULL AND "rg"."entity_id" IS NULL|, reversed_params}
  end

  # A rule's own roles are held on the row itself or on its whole type - the lookup matches
  # both shapes, which the store keeps apart by whether its entity_id column is nil.
  defp grant_scope_sql({:own, _role_names}, context, reversed_params) do
    {placeholder, new_params} =
      entity_type_slot(context.entity_type, context, reversed_params)

    resource_sql =
      ~s|("rg"."entity_id" = #{context.row_prefix}."id" OR "rg"."entity_id" IS NULL)|

    {~s|"rg"."entity_type" = #{placeholder} AND #{resource_sql}|, new_params}
  end

  # The grant store's own policy checks a role held on the resource a grant row names, so the
  # lookup keys on the outer row's entity_id column rather than on a relationship reference.
  defp grant_scope_sql({:resource, target_type, _role_names}, context, reversed_params) do
    {placeholder, new_params} = entity_type_slot(target_type, context, reversed_params)

    scope_sql =
      ~s|"rg"."entity_type" = #{placeholder} | <>
        ~s|AND "rg"."entity_id" = #{context.row_prefix}."entity_id"|

    {scope_sql, new_params}
  end

  defp grant_scope_sql({:type, target_type, _role_names}, context, reversed_params) do
    {placeholder, new_params} = entity_type_slot(target_type, context, reversed_params)

    {~s|"rg"."entity_type" = #{placeholder} AND "rg"."entity_id" IS NULL|, new_params}
  end

  defp grant_scope_sql({:rel, relationship_name, _role_names}, context, reversed_params) do
    column = reference_column(context.entity_mapping, relationship_name)

    {placeholder, new_params} =
      entity_type_slot(
        relationship_target(context.entity_type, relationship_name),
        context,
        reversed_params
      )

    quoted_column = Mapper.quote_identifier(column.name)

    scope_sql =
      ~s|"rg"."entity_type" = #{placeholder} | <>
        ~s|AND "rg"."entity_id" = #{context.row_prefix}.#{quoted_column}|

    {scope_sql, new_params}
  end

  defp grant_table(context) do
    table =
      context.mapping
      |> Map.fetch!(RoleGrant)
      |> Map.fetch!(:table)

    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(table)}"
  end

  defp group_condition([rule_sql]), do: rule_sql

  defp group_condition(rule_sqls) do
    "(" <> Enum.map_join(rule_sqls, " OR ", &"(#{&1})") <> ")"
  end

  # Delegation asks the related entity's policy for the same operation, composed into a
  # correlated EXISTS. Recursion terminates because delegation cycles are a compile error, so
  # every chain reaches a type that delegates no further.
  defp delegation_conditions(nil, _context, reversed_params), do: {[], reversed_params}

  defp delegation_conditions(relationship_name, context, reversed_params) do
    column = reference_column(context.entity_mapping, relationship_name)
    target_type = relationship_target(context.entity_type, relationship_name)
    target_mapping = Map.fetch!(context.mapping, target_type)

    target_rules =
      target_type
      |> Policy.build()
      |> Map.get(context.operation, [])

    target_policy = %{
      anonymous?: context.anonymous?,
      operation: context.operation,
      rules: target_rules
    }

    target_context = policy_context(target_type, context.mapping, target_policy)

    {target_conditions, new_params} =
      policy_conditions(target_policy, target_context, reversed_params)

    join_sql =
      ~s|#{Mapper.quote_identifier(target_mapping.table)}."id" = | <>
        ~s|#{context.row_prefix}.#{Mapper.quote_identifier(column.name)}|

    inner_sql = Enum.join([join_sql | target_conditions], " AND ")

    condition =
      ~s|EXISTS (SELECT 1 FROM #{Mapper.quote_identifier(@data_schema)}.| <>
        ~s|#{Mapper.quote_identifier(target_mapping.table)} WHERE #{inner_sql})|

    {[condition], new_params}
  end

  defp rule_condition(rule, context, reversed_params) do
    {predicate_conditions, params_after_predicates} =
      conditions(rule.predicates, context.entity_mapping, reversed_params)

    {reference_conditions, params_after_references} =
      grant_reference_conditions(rule.to, context, params_after_predicates)

    {delegation_conditions, new_params} =
      delegation_conditions(rule.via, context, params_after_references)

    rule_conditions = predicate_conditions ++ reference_conditions ++ delegation_conditions

    case rule_conditions do
      [] -> {:unconditional, new_params}
      conditions -> {Enum.join(conditions, " AND "), new_params}
    end
  end

  # Holding any of a rule's grant references satisfies it, so the references render as one
  # OR group of EXISTS lookups against the grant store.
  defp grant_reference_conditions(nil, _context, reversed_params), do: {[], reversed_params}

  defp grant_reference_conditions(references, context, reversed_params) do
    {rendered, new_params} =
      Enum.map_reduce(references, reversed_params, fn reference, acc_params ->
        grant_exists_condition(reference, context, acc_params)
      end)

    {[group_condition(rendered)], new_params}
  end

  defp conditions(triples, entity_mapping, reversed_params) do
    Enum.map_reduce(triples, reversed_params, fn triple, acc_params ->
      condition(triple, entity_mapping, acc_params)
    end)
  end

  # The bound binds twice: once folded the way the column's key is, once raw. The key slot is
  # pushed first, so the pair reads left to right in the statement.
  defp sort_key_slots({:placeholder, placeholder_name}, reversed_params) do
    {key_slot, params_with_key} =
      bind_placeholder_slot(placeholder_name, :sort_key, reversed_params)

    {raw_slot, new_params} = bind_placeholder_slot(placeholder_name, :string, params_with_key)

    {key_slot, raw_slot, new_params}
  end

  defp sort_key_slots(literal, reversed_params) do
    encoded_value = Codec.encode(literal, :string)

    {key_slot, params_with_key} =
      bind_slot_value(SortKey.compute(encoded_value), reversed_params)

    {raw_slot, new_params} = bind_slot_value(encoded_value, params_with_key)

    {key_slot, raw_slot, new_params}
  end

  defp bind_placeholder_slot(placeholder_name, type, reversed_params) do
    {"$#{length(reversed_params) + 1}",
     [{:placeholder, placeholder_name, type} | reversed_params]}
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

  defp membership_slot({:placeholder, placeholder_name}, column, reversed_params) do
    {"$#{length(reversed_params) + 1}",
     [{:placeholder, placeholder_name, {:list, column.type}} | reversed_params]}
  end

  # A list holding placeholder elements binds one slot per element inside an ARRAY
  # constructor - each element placeholder is a scalar slot of the attribute's type.
  defp membership_slot(values, column, reversed_params) do
    if Enum.any?(values, &match?({:placeholder, _placeholder_name}, &1)) do
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

  defp include_expression({name, sub_term}, parent_mapping, mapping, policy, parent_prefix, acc) do
    join_table = Enum.find(parent_mapping.join_tables, &(&1.relationship == name))

    if join_table do
      to_many_include_expression(sub_term, join_table, mapping, policy, parent_prefix, acc)
    else
      to_one_include_expression(
        name,
        sub_term,
        parent_mapping,
        mapping,
        policy,
        parent_prefix,
        acc
      )
    end
  end

  defp include_pairs(term, target_mapping, mapping, policy, quoted_alias, acc) do
    {fragments, new_acc} =
      term.include
      |> Enum.sort_by(fn {entry_name, _sub_term} -> entry_name end)
      |> Enum.map_reduce(acc, fn {entry_name, _sub_term} = entry, inner_acc ->
        {expression, next_acc} =
          include_expression(entry, target_mapping, mapping, policy, quoted_alias, inner_acc)

        {", '#{entry_name}', #{expression}", next_acc}
      end)

    {Enum.join(fragments, ""), new_acc}
  end

  # An include embeds rows of the target type, so every level composes that type's :read policy,
  # fixed at :read regardless of the operation the statement's own policy carries.
  defp include_policy(nil, _entity_type), do: nil

  defp include_policy(policy, entity_type) do
    %{
      anonymous?: Map.get(policy, :anonymous?, false),
      operation: :read,
      rules:
        entity_type
        |> Policy.build()
        |> Map.get(:read, [])
    }
  end

  defp include_selects(
         %{cardinality: :count},
         _entity_mapping,
         _mapping,
         _policy,
         reversed_params
       ) do
    {"", reversed_params}
  end

  defp include_selects(term, entity_mapping, mapping, policy, reversed_params) do
    quoted_prefix = Mapper.quote_identifier(entity_mapping.table)

    {fragments, {new_params, _next_index}} =
      term.include
      |> Enum.sort_by(fn {name, _sub_term} -> name end)
      |> Enum.map_reduce({reversed_params, 1}, fn {name, _sub_term} = entry, acc ->
        {expression, new_acc} =
          include_expression(entry, entity_mapping, mapping, policy, quoted_prefix, acc)

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

  defp companion_column(entity_mapping, name) do
    Enum.find(entity_mapping.columns, &(&1.source == {:sort_key, name}))
  end

  defp order_column_names(entity_mapping, name) do
    column = fetch_column!(entity_mapping, name)
    companion = companion_column(entity_mapping, name)

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
         policy,
         parent_prefix,
         {reversed_params, index}
       ) do
    target_mapping = Map.fetch!(mapping, sub_term.entity)
    quoted_wrapper = Mapper.quote_identifier("i#{index}")
    quoted_join = Mapper.quote_identifier("j#{index}")
    quoted_target = Mapper.quote_identifier("t#{index}")

    {conditions, filtered_params} = conditions(sub_term.filter, target_mapping, reversed_params)

    target_policy = include_policy(policy, sub_term.entity)

    {policy_conditions, policied_params} =
      policy_conditions(
        target_policy,
        policy_context(sub_term.entity, mapping, target_policy, quoted_target),
        filtered_params
      )

    filter_sql = Enum.map_join(conditions ++ policy_conditions, "", &(" AND " <> &1))

    {nested_pairs, new_acc} =
      include_pairs(
        sub_term,
        target_mapping,
        mapping,
        policy,
        quoted_wrapper,
        {policied_params, index + 1}
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
         policy,
         parent_prefix,
         {reversed_params, index}
       ) do
    reference_column =
      Enum.find(parent_mapping.columns, &(&1.source == {:relationship, name}))

    target_mapping = Map.fetch!(mapping, sub_term.entity)
    quoted_alias = Mapper.quote_identifier("i#{index}")

    target_policy = include_policy(policy, sub_term.entity)

    {policy_conditions, policied_params} =
      policy_conditions(
        target_policy,
        policy_context(sub_term.entity, mapping, target_policy, quoted_alias),
        reversed_params
      )

    policy_sql = Enum.map_join(policy_conditions, "", &(" AND " <> &1))

    {nested_pairs, new_acc} =
      include_pairs(
        sub_term,
        target_mapping,
        mapping,
        policy,
        quoted_alias,
        {policied_params, index + 1}
      )

    expression =
      "(SELECT jsonb_build_object(#{jsonb_pairs(target_mapping, quoted_alias)}#{nested_pairs}) " <>
        "FROM #{qualified_table(target_mapping.table)} AS #{quoted_alias} " <>
        ~s|WHERE #{quoted_alias}."id" = #{parent_prefix}.#{Mapper.quote_identifier(reference_column.name)}| <>
        policy_sql <> ")"

    {expression, new_acc}
  end

  defp where_clause([]), do: ""

  defp where_clause(conditions), do: " WHERE " <> Enum.join(conditions, " AND ")
end
