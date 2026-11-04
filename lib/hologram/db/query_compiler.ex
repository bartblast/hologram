defmodule Hologram.DB.QueryCompiler do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.DB.SortKey
  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Policy
  alias Hologram.Query

  @quantifiers [:all, :any, :none]

  # Each search operator as the shape of the pattern it matches and how it matches the bytes.
  @search_operators %{
    contains: {:infix, :loose},
    contains_exact: {:infix, :exact},
    starts_with: {:prefix, :loose},
    starts_with_exact: {:prefix, :exact}
  }

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
  slot. Column selection follows the mapping's physical column order, leaving out the derived
  sort-key and search-key companions, which a reader never reads back.

  Cardinality shapes the statement: `:set` selects the mapped columns with ordering
  and view bounds, `:one` selects with `LIMIT 1` under the query's total order (a
  zero take stays zero), and `:count` selects `count(*)` - over a capped subquery
  when view bounds are set, since a counting query counts what it evaluates to.
  Counting queries carry no includes - an embedded entity cannot change the count.

  Includes compile into correlated jsonb subselects - one per included relationship,
  in sorted name order, each aliased distinctly (self-referencing relationships stay
  unambiguous - the root table is addressed by name). The jsonb keys are the target's
  physical column names in mapping order, derived companions left out. A to-one subselect is
  NULL when the reference is. A to-many subselect aggregates the related set through its join table
  into a jsonb array (empty set = empty array), applying the sub-term's filter,
  ordering, and view bounds inside the aggregation - include param slots follow the
  root's in parameter order. An inverse is read from where the relationship it reverses is
  stored: an inverse set of a to-one aggregates the related rows whose reference names the
  row, an inverse set of a to-many the related rows whose join table pairs name it as the
  target, each like a to-many, and a single inverse is the one related row whose reference
  names the row, like a to-one.

  An included derived field holding a value is a select column - a jsonb pair under a related row
  - computed from its definition on the row it belongs to. One holding rows embeds its
  definition's rows the way an include embeds a relationship's, aliased alike: a set aggregated in
  the definition's order with its bounds applied, one row the first in that order, each row
  embedding what the definition includes beside the include's nested includes. An `if` choosing
  between definitions is a `CASE WHEN`, and nil is an empty array or NULL. When a policy is given,
  the related type's `:read` policy applies inside, as it does for any include.

  A compiled policy composes into the statement when one is given: its rules render as an
  OR group ANDed after the authored filter, so a row must satisfy the query and at least one
  rule. Rules hold the same clauses the authored filter does, a disjunction among them nesting
  one level deeper, and an unconditional rule (no conditions) satisfies the group on its own,
  which drops the group from the statement. An empty rule list denies everything (`FALSE`) -
  default deny. The actor leaf binds ONE reserved slot allocated after the authored and include
  params and reused by every actor reference in the policy, so the caller binds the session's
  user once.

  An anonymous statement binds no actor at all. A predicate naming the actor is false for nobody,
  whichever way it points, and a grant reference is held by nobody, so those are folded away
  before rendering: a rule with grant references is dropped, a conjunction naming the actor is
  dropped, and a disjunction keeps its alternatives that name nobody - so
  `author_id == user_id() or shared == true` still admits a visitor to the shared rows.

  Includes are policied too, at every nesting level: an include subquery ANDs the included
  type's :read policy - fixed at :read whatever rules the statement's own policy holds - keyed
  on the include's alias rather than the target table name. A to-one embed the acting user
  cannot read is NULL, and rows they cannot read drop out of a to-many aggregate before its view
  bounds apply. Compiling without a policy leaves every level unfiltered - the trusted tier.

  Nil is a regular value for equality and membership on both execution tiers:
  inequality matches missing values (`!=` widens with `OR IS NULL` on optional
  attributes), membership lists may hold nil (compiled into the `IS [NOT] NULL`
  branch alongside the stripped array), and negated membership without nil matches
  missing values. Ordering comparisons match actual values only. Param slots never
  bind nil at runtime - a sometimes-nil variable branches into an explicit nil
  predicate in code.

  A comparison between two attributes of the row binds no slot. Equality compiles to
  `IS NOT DISTINCT FROM` and inequality to `IS DISTINCT FROM`, so nil keeps its meaning,
  and an ordering comparison compiles to a plain column comparison, matching no row with
  either side missing. Two strings compare their sort-key pairs, `("a_$sort", "a") <
  ("b_$sort", "b")`, and an enum operand is cast to the compared attribute's enum type by
  label.

  A search compiles to a LIKE: an exact one over the column, a loose one over
  `COALESCE("a_$search", "a_$sort")` - the whole folded value, which the search key holds when the
  sort key's prefix can't. The term binds as a pattern, folded for a loose match and with `\\`, `%`
  and `_` escaped, so they are plain characters - a placeholder term binds a
  `{:pattern, :prefix | :infix, :exact | :loose}` slot the runner builds the pattern for. A search
  for another attribute's value can't be a pattern, so it compiles to `strpos`: `= 1` for a
  prefix, `> 0` for a substring. NULL on either side matches no row, and an empty term or value
  matches every row with a value.

  A path - on either side of a comparison - compiles to nested scalar subqueries, one per
  relationship it follows, each aliased `"$p<n>"` and correlated on the row before it, the
  innermost selecting the column the path ends at. A subquery finding no row yields NULL, so a
  path through an empty relationship, a row that is gone or one the read policy hides reads as a
  missing value, and the nil rules above apply to it as to an optional attribute. When a policy
  is given, each hop ANDs its type's :read policy, keyed on its alias, the way an include does - a
  policy rule's own condition reads the rows its paths reach raw. A hop's policy binds its own
  slots inside the hop, so under a policy a comparison on a path binds them even where the same
  comparison on an attribute binds none.

  A quantifier compiles to a correlated subquery over the related table, aliased `"$q<n>"` by its
  nesting depth: `EXISTS` of the related rows matching its condition for `any`, `NOT EXISTS` of
  them for `none`, and `NOT EXISTS` of the related rows its condition is not true of for `all` -
  `IS NOT TRUE`, so a row the condition compares against nil counts against `all`, the way the
  comparison passes over nil everywhere else. The related rows are the ones the set's join table
  pairs with the row, or whose reference field names it, or the rows a derived field holding them
  holds, the row reached through the source's to-one relationships first - a hop finding no row
  leaves the set empty. When a policy is given,
  the related type's `:read` policy applies inside the subquery, so a row the session may not read
  is not among them. Inside the condition the related row's columns are the subquery's, and a name
  of a row above is qualified with the name the statement gives that row.

  A derived field holding a value is computed from its definition wherever its name is read - a
  subject, an operand, a path's end, a sort entry - so the database still runs one statement. A
  literal binds a slot cast to the declared type, a name reads what it names (an enum attribute
  as its label, an integer read by a float field widened), `<>` is `||`, so a missing operand
  makes the whole value missing, `if` is `CASE WHEN`, taking the else branch when its condition
  is not true, and a condition is `COALESCE(..., false)`, never missing. Any other computed value
  can be missing, so the nil rules of an optional attribute apply to it. A computed enum is its
  label, and it orders and compares by the label's position among the declared ones.

  A count a derived field holds compiles to a `(SELECT count(*) ...)` subquery, aliased `"$s<n>"`
  by how deep it nests and correlated on the row that holds the field - which its clauses reach as
  the row above, the way a quantifier's condition reaches the row its source starts at - its
  bounds capping the rows counted. Its rows are the ones its source leads to from that row: the
  last link's rows of every row the links before it reach, each such row matched with `EXISTS`, so
  a set before the last is flattened and a row several paths reach is counted once. A missing
  related row leads nowhere, so a count through one is 0. A derived field holding rows matches a
  row with `IN` over its rows - bounded in its order - an `if` choosing between such sets with
  `CASE WHEN`, and nil holding no rows. When a policy is given, the read policy applies to the
  counted rows and to every row along the way, so a row the session may not read is not among
  them and leads nowhere.
  """
  @spec compile(Query.t(), %{module => %{atom => any}}, %{atom => any} | nil) ::
          %{atom => any}
  def compile(term, mapping, policy \\ nil) do
    entity_mapping = Map.fetch!(mapping, term.entity)

    quoted_table = Mapper.quote_identifier(entity_mapping.table)
    statement_scope = condition_scope(term.entity, mapping, quoted_table, policy)

    {authored_conditions, authored_params} = conditions(term.filter, statement_scope, [])

    {include_sql, params_after_includes} =
      include_selects(term, entity_mapping, mapping, policy, authored_params)

    {policy_conditions, params_after_policy} =
      policy_conditions(
        policy,
        policy_context(term.entity, mapping, policy),
        params_after_includes
      )

    {order_sql, all_reversed_params} =
      order_clause(term.sort, statement_scope, params_after_policy)

    where_sql = where_clause(authored_conditions ++ policy_conditions)
    sql = statement(term, entity_mapping, where_sql, order_sql, include_sql)

    %{params: Enum.reverse(all_reversed_params), sql: sql}
  end

  @doc """
  Returns the LIKE pattern a search binds for the given term: the term - folded first for a loose
  match - with `\\`, `%` and `_` escaped, followed by `%` for a prefix and surrounded by `%` for a
  substring.
  """
  @spec search_pattern(String.t(), :infix | :prefix, :exact | :loose) :: String.t()
  def search_pattern(term, shape, mode) do
    escaped =
      term
      |> fold_term(mode)
      |> String.replace(["\\", "%", "_"], &("\\" <> &1))

    case shape do
      :infix -> "%#{escaped}%"
      :prefix -> "#{escaped}%"
    end
  end

  # Binding nil for the actor would answer it as a value, and author_id != user_id() renders
  # null-inclusively, matching every row with no author - so an anonymous statement folds what
  # nobody satisfies away instead: the same answer the interpreter and the policy evaluator give,
  # a predicate naming the actor false for nobody. A clause folds to :never, or to the clauses that
  # remain of it - a disjunction keeping one alternative leaves that alternative's clauses in its
  # place.
  defp anonymous_clause({:or, alternatives}) do
    kept =
      Enum.flat_map(alternatives, fn alternative ->
        case anonymous_clauses(alternative) do
          :never -> []
          {:ok, clauses} -> [clauses]
        end
      end)

    case kept do
      [] -> :never
      [clauses] -> {:ok, clauses}
      several -> {:ok, [{:or, several}]}
    end
  end

  defp anonymous_clause({_name, _operator, {:actor}}), do: :never

  defp anonymous_clause(triple), do: {:ok, [triple]}

  defp anonymous_clauses(clauses) do
    Enum.reduce_while(clauses, {:ok, []}, fn clause, {:ok, kept} ->
      case anonymous_clause(clause) do
        :never -> {:halt, :never}
        {:ok, folded} -> {:cont, {:ok, kept ++ folded}}
      end
    end)
  end

  # A role is held by somebody, so a rule naming one never admits nobody.
  defp anonymous_rule(%{to: to}) when to != nil, do: []

  defp anonymous_rule(rule) do
    case anonymous_clauses(rule.predicates) do
      :never -> []
      {:ok, clauses} -> [%{rule | predicates: clauses}]
    end
  end

  # An anonymous statement keeps what nobody can satisfy out of the statement rather than binding
  # a nil placeholder - at every nesting level, delegated policies included.
  defp applicable_rules(rules, %{anonymous?: true}), do: Enum.flat_map(rules, &anonymous_rule/1)

  defp applicable_rules(rules, _context), do: rules

  # Bind slots inside an ARRAY constructor carry no type context of their own -
  # without the cast Postgres resolves them to text.
  defp array_type(%{source: :derived, sql_type: sql_type}), do: "#{sql_type}[]"

  defp array_type(%{type: :enum, sql_type: sql_type}) do
    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(sql_type)}[]"
  end

  defp array_type(%{sql_type: sql_type}), do: "#{sql_type}[]"

  # Every enum attribute is a type of its own, and Postgres compares no two of them - so the other
  # column is cast to the compared column's type, by label, and the two compare in the declared
  # order they share. A computed enum is its label, so the other side is read as one too.
  defp attribute_operand_sql(scope, column, other, reversed_params) do
    {other_sql, other_column, new_params} = subject_sql(scope, other, reversed_params)

    cond do
      column.type != :enum ->
        {other_sql, new_params}

      column.source == :derived ->
        {cast_sql(other_sql, other_column, column), new_params}

      other_column.source == :derived ->
        {"#{other_sql}::#{enum_type(column)}", new_params}

      true ->
        {"#{other_sql}::text::#{enum_type(column)}", new_params}
    end
  end

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
    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(sql_type)}"
  end

  defp bind_slot_value(encoded_value, reversed_params) do
    {"$#{length(reversed_params) + 1}", [{:value, encoded_value} | reversed_params]}
  end

  defp bounds_clause(term) do
    limit_sql = if term.take, do: " LIMIT #{term.take}", else: ""
    offset_sql = if term.skip, do: " OFFSET #{term.skip}", else: ""

    limit_sql <> offset_sql
  end

  # A name read by a derived field as its declared type: an enum attribute as its label, an integer
  # read by a float field widened.
  defp cast_sql(sql, %{sql_type: sql_type}, %{sql_type: sql_type}), do: sql

  defp cast_sql(sql, _from_column, to_column), do: "#{sql}::#{to_column.sql_type}"

  # The id of the row a chain of relationships leads to, read off the row a policy is evaluated for:
  # the reference column itself for one relationship, and for a path the last reference read
  # through the hops before it, raw - a policy decides by the rows as stored.
  defp chain_target_id_sql(context, [relationship_name], reversed_params) do
    column = reference_column(context.entity_mapping, relationship_name)

    {"#{context.row_prefix}.#{Mapper.quote_identifier(column.name)}", reversed_params}
  end

  defp chain_target_id_sql(context, relationship_names, reversed_params) do
    last_name = List.last(relationship_names)
    reference_field = String.to_existing_atom("#{last_name}_id")
    reference_path = List.replace_at(relationship_names, -1, reference_field)

    scope =
      condition_scope(
        context.entity_type,
        context.mapping,
        context.row_prefix,
        nil,
        context.path_depth,
        context.delegation_depth
      )

    {target_id_sql, _column, new_params} =
      path_sql(scope, reference_path, &fetch_column!/2, reversed_params)

    {target_id_sql, new_params}
  end

  # The first of the given columns holding a value, qualified with the given row's name when one is
  # given - a loose search reads the search key, or the sort key when there is none.
  defp coalesced_sql(quoted_prefix, columns) do
    qualified_columns =
      Enum.map_join(columns, ", ", fn column ->
        quoted_column = Mapper.quote_identifier(column.name)

        if quoted_prefix, do: "#{quoted_prefix}.#{quoted_column}", else: quoted_column
      end)

    "COALESCE(#{qualified_columns})"
  end

  # A derived companion is never read back - a reader recomputes it from the value beside it - so
  # neither a row's column list nor an embedded row's object carries one.
  defp column_list(entity_mapping) do
    entity_mapping.columns
    |> Enum.reject(&Mapper.derived?/1)
    |> Enum.map_join(", ", &Mapper.quote_identifier(&1.name))
  end

  defp column_sql(%{qualified: true} = scope, column) do
    "#{scope.row_prefix}.#{Mapper.quote_identifier(column.name)}"
  end

  defp column_sql(_scope, column), do: Mapper.quote_identifier(column.name)

  # A quantifier is a correlated subquery over the related rows its source leads to - see the
  # moduledoc for what each one asks of them.
  defp condition({quantifier, {source, clauses}}, scope, reversed_params)
       when quantifier in @quantifiers do
    depth = scope.quantifier_depth + 1
    quoted_alias = Mapper.quote_identifier("$q#{depth}")
    quoted_join = Mapper.quote_identifier("$qj#{depth}")

    {target_type, membership_sql, params_after_owner} =
      quantified_set(scope, source, quoted_alias, quoted_join, reversed_params)

    inner_scope =
      target_type
      |> condition_scope(
        scope.mapping,
        quoted_alias,
        scope.policy,
        scope.path_depth,
        scope.delegation_depth
      )
      |> Map.merge(%{
        outer: [scope | scope.outer],
        quantifier_depth: depth,
        source_depth: scope.source_depth
      })

    {policy_conditions, params_after_policy} =
      path_policy_conditions(
        scope,
        target_type,
        quoted_alias,
        scope.path_depth,
        params_after_owner
      )

    {inner_conditions, new_params} = conditions(clauses, inner_scope, params_after_policy)

    where_sql =
      [membership_sql]
      |> Enum.concat(policy_conditions)
      |> Enum.concat(quantified_conditions(quantifier, inner_conditions))
      |> Enum.join(" AND ")

    target_table = Map.fetch!(scope.mapping, target_type).table

    exists_sql =
      "EXISTS (SELECT 1 FROM #{qualified_table(target_table)} AS #{quoted_alias} WHERE #{where_sql})"

    if quantifier == :any do
      {exists_sql, new_params}
    else
      {"NOT " <> exists_sql, new_params}
    end
  end

  # A disjunction renders the way a policy's rules do, as an OR group of its alternatives, each a
  # conjunction - so a rule whose condition holds one nests one level deeper.
  defp condition({:or, alternatives}, scope, reversed_params) do
    {rendered, new_params} =
      Enum.map_reduce(alternatives, reversed_params, fn alternative, acc_params ->
        {alternative_conditions, next_params} = conditions(alternative, scope, acc_params)

        {Enum.join(alternative_conditions, " AND "), next_params}
      end)

    {group_condition(rendered), new_params}
  end

  # A search for another attribute's value can't put that value in a pattern - its % and _ would
  # read as wildcards - so it asks where the value first occurs: at the start for a prefix,
  # anywhere for a substring. NULL on either side is unknown, so a row with no value never matches,
  # and an empty value occurs at the start of every string, as an empty term matches every row.
  defp condition({name, operator, {:attribute, other}}, scope, reversed_params)
       when is_map_key(@search_operators, operator) do
    {shape, mode} = Map.fetch!(@search_operators, operator)
    {subject_sql, params_after_subject} = search_subject_sql(scope, name, mode, reversed_params)
    {operand_sql, new_params} = search_subject_sql(scope, other, mode, params_after_subject)
    position_sql = "strpos(#{subject_sql}, #{operand_sql})"

    condition_sql =
      case shape do
        :infix -> "#{position_sql} > 0"
        :prefix -> "#{position_sql} = 1"
      end

    {condition_sql, new_params}
  end

  # A search is a LIKE over the value - or over its whole folded form for a loose match - with the
  # term escaped into a pattern, so its % and _ are plain characters. A pinned term is escaped
  # when it binds.
  defp condition({name, operator, term}, scope, reversed_params)
       when is_map_key(@search_operators, operator) do
    {shape, mode} = Map.fetch!(@search_operators, operator)
    {subject_sql, params_after_subject} = search_subject_sql(scope, name, mode, reversed_params)

    {pattern_slot, new_params} =
      case term do
        {:placeholder, placeholder_name} ->
          bind_placeholder_slot(placeholder_name, {:pattern, shape, mode}, params_after_subject)

        literal ->
          literal
          |> search_pattern(shape, mode)
          |> bind_slot_value(params_after_subject)
      end

    {"#{subject_sql} LIKE #{pattern_slot}", new_params}
  end

  # Two columns of one row. SQL's = and != are unknown when either side is NULL, so the equality
  # family uses the DISTINCT forms, which read nil as a value - the meaning a literal comparison
  # has. An ordering comparison is unknown over a NULL on its own, which is the meaning it has too.
  defp condition({name, :==, {:attribute, other}}, scope, reversed_params) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)
    {operand_sql, new_params} = attribute_operand_sql(scope, column, other, params_after_subject)

    {"#{subject_sql} IS NOT DISTINCT FROM #{operand_sql}", new_params}
  end

  defp condition({name, :!=, {:attribute, other}}, scope, reversed_params) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)
    {operand_sql, new_params} = attribute_operand_sql(scope, column, other, params_after_subject)

    {"#{subject_sql} IS DISTINCT FROM #{operand_sql}", new_params}
  end

  # Two strings compare by the pairs their ordering sorts by, each side its own key and value, so
  # the comparison agrees with ORDER BY on both columns.
  defp condition({name, operator, {:attribute, other}}, scope, reversed_params) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)

    case sort_key_sql(scope, name, params_after_subject) do
      {nil, params_after_key} ->
        {operand_sql, new_params} = attribute_operand_sql(scope, column, other, params_after_key)

        condition_sql =
          "#{position_sql(subject_sql, column)} #{operator} #{position_sql(operand_sql, column)}"

        {condition_sql, new_params}

      {subject_key_sql, params_after_key} ->
        {operand_key_sql, params_after_operand_key} = sort_key_sql(scope, other, params_after_key)

        {operand_sql, _operand_column, new_params} =
          subject_sql(scope, other, params_after_operand_key)

        condition_sql =
          "(#{subject_key_sql}, #{subject_sql}) #{operator} (#{operand_key_sql}, #{operand_sql})"

        {condition_sql, new_params}
    end
  end

  defp condition({name, :==, nil}, scope, reversed_params) do
    {subject_sql, _column, new_params} = subject_sql(scope, name, reversed_params)

    {"#{subject_sql} IS NULL", new_params}
  end

  defp condition({name, :==, value}, scope, reversed_params) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)
    {placeholder, new_params} = bind_slot(value, column, params_after_subject)

    {"#{subject_sql} = #{placeholder}", new_params}
  end

  defp condition({name, :!=, nil}, scope, reversed_params) do
    {subject_sql, _column, new_params} = subject_sql(scope, name, reversed_params)

    {"#{subject_sql} IS NOT NULL", new_params}
  end

  defp condition({name, :!=, value}, scope, reversed_params) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)
    {placeholder, new_params} = bind_slot(value, column, params_after_subject)

    condition_sql = "#{subject_sql} != #{placeholder}"

    {null_inclusive(condition_sql, subject_sql, column), new_params}
  end

  defp condition({name, :in, values}, scope, reversed_params) when is_list(values) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)

    case Enum.reject(values, &is_nil/1) do
      [] ->
        {"#{subject_sql} IS NULL", params_after_subject}

      ^values ->
        {placeholder, new_params} = membership_slot(values, column, params_after_subject)

        {"#{subject_sql} = ANY(#{placeholder})", new_params}

      stripped_values ->
        {placeholder, new_params} = membership_slot(stripped_values, column, params_after_subject)

        condition_sql = "#{subject_sql} = ANY(#{placeholder})"

        {null_inclusive(condition_sql, subject_sql, column), new_params}
    end
  end

  defp condition({name, :in, operand}, scope, reversed_params) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)
    {placeholder, new_params} = membership_slot(operand, column, params_after_subject)

    {"#{subject_sql} = ANY(#{placeholder})", new_params}
  end

  defp condition({name, :not_in, values}, scope, reversed_params) when is_list(values) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)

    case Enum.reject(values, &is_nil/1) do
      [] ->
        {"#{subject_sql} IS NOT NULL", params_after_subject}

      ^values ->
        {placeholder, new_params} = membership_slot(values, column, params_after_subject)

        condition_sql = "#{subject_sql} != ALL(#{placeholder})"

        {null_inclusive(condition_sql, subject_sql, column), new_params}

      stripped_values ->
        {placeholder, new_params} = membership_slot(stripped_values, column, params_after_subject)

        condition_sql = "#{subject_sql} != ALL(#{placeholder})"

        {maybe_require_value(condition_sql, subject_sql, column), new_params}
    end
  end

  defp condition({name, :not_in, operand}, scope, reversed_params) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)
    {placeholder, new_params} = membership_slot(operand, column, params_after_subject)

    condition_sql = "#{subject_sql} != ALL(#{placeholder})"

    {null_inclusive(condition_sql, subject_sql, column), new_params}
  end

  # A string compares by the pair its ordering sorts by - the key carries the order and the value
  # settles what the key cannot - so a bound is a position in the list the attribute sorts into,
  # and the comparison agrees with ORDER BY by construction. A computed enum compares by its
  # label's declared position, and every other type by its value alone.
  defp condition({name, operator, value}, scope, reversed_params) do
    {subject_sql, column, params_after_subject} = subject_sql(scope, name, reversed_params)

    case sort_key_sql(scope, name, params_after_subject) do
      {nil, params_after_key} ->
        {placeholder, new_params} = bind_slot(value, column, params_after_key)

        condition_sql =
          "#{position_sql(subject_sql, column)} #{operator} #{position_sql(placeholder, column)}"

        {condition_sql, new_params}

      {subject_key_sql, params_after_key} ->
        {key_slot, raw_slot, new_params} = sort_key_slots(value, params_after_key)

        condition_sql =
          "(#{subject_key_sql}, #{subject_sql}) #{operator} (#{key_slot}, #{raw_slot})"

        {condition_sql, new_params}
    end
  end

  # Where a condition is rendered: the row it is about - its type, its mapping, and the name the
  # statement gives it - and how a path reads a related row there. Under a statement's policy a
  # hop applies the hop type's read policy, so an unreadable related row reads as a missing one,
  # and inside a policy rule (no policy) hops read the related rows raw, as delegation does. The
  # depths name the aliases a nested path, delegation, quantifier or derived field's rows take, so
  # none shadows a row an enclosing subquery correlates on. Inside a quantifier's condition the
  # scope is the related row's, and the scopes of the rows above it are kept, nearest first, for the
  # names that reach them. A row above is read with its columns qualified with its name, since
  # inside a quantifier the unqualified ones are the related row's. The row a path ends at and an
  # include's wrapper are read qualified too.
  defp condition_scope(
         entity_type,
         mapping,
         quoted_row_prefix,
         policy,
         path_depth \\ 0,
         delegation_depth \\ 0
       ) do
    %{
      delegation_depth: delegation_depth,
      entity_mapping: Map.fetch!(mapping, entity_type),
      entity_type: entity_type,
      mapping: mapping,
      outer: [],
      path_depth: path_depth,
      policy: policy,
      qualified: false,
      quantifier_depth: 0,
      row_prefix: quoted_row_prefix,
      source_depth: 0
    }
  end

  # How a row related through the given relationship is matched to the parent row: a set's rows
  # through the reference or the join table that pairs them, a single row through the reference
  # naming it or naming the parent.
  defp relationship_membership(parent_type, parent_mapping, name, mapping, parent_prefix) do
    join_table = Enum.find(parent_mapping.join_tables, &(&1.relationship == name))
    inverse = Entity.inverse_relationship(parent_type, name)
    parent_id_sql = ~s|#{parent_prefix}."id"|

    cond do
      inverse && inverse.to_many? ->
        {:to_many, inverse_membership(inverse, mapping, parent_id_sql)}

      inverse ->
        {:to_one, inverse_match(inverse, mapping, parent_prefix)}

      join_table ->
        {:to_many, join_membership(join_table, parent_id_sql)}

      true ->
        {:to_one, reference_match(name, parent_mapping, parent_prefix)}
    end
  end

  defp relationship_target(entity_type, relationship_name) do
    {_name, target_type, _opts} =
      Enum.find(entity_type.__relationships__(), fn {name, _type, _opts} ->
        name == relationship_name
      end)

    target_type
  end

  # A to-one's related row: the one its reference column names.
  defp reference_match(name, parent_mapping, parent_prefix) do
    column = Enum.find(parent_mapping.columns, &(&1.source == {:relationship, name}))

    fn quoted_alias ->
      ~s|#{quoted_alias}."id" = #{parent_prefix}.#{Mapper.quote_identifier(column.name)}|
    end
  end

  defp reference_column(entity_mapping, relationship_name) do
    Enum.find(entity_mapping.columns, &(&1.source == {:relationship, relationship_name}))
  end

  defp reference_role_names({:global, role_modules}), do: role_modules

  defp reference_role_names({:own, role_names}), do: role_names

  defp reference_role_names({:type, _target_type, role_names}), do: role_names

  defp reference_role_names({:rel, _relationship_names, role_names}), do: role_names

  defp reference_role_names({:named, _target_type, role_names}), do: role_names

  # The entity type enum's values ARE the entity type modules, so a type binds as its own enum
  # label - the same string the client compares a grant row against.
  defp entity_type_slot(entity_type, context, reversed_params) do
    column = grant_column(context, "entity_type")

    {placeholder, new_params} =
      bind_slot_value(Codec.encode_enum_value(entity_type), reversed_params)

    {"#{placeholder}::#{enum_type(column)}", new_params}
  end

  # The id of the row a quantifier's set belongs to: the scope's own row, or the row its to-one
  # relationships lead to - NULL when one of them finds no row, which leaves the set empty.
  defp owner_id_sql(scope, [], reversed_params),
    do: {~s|#{scope.row_prefix}."id"|, reversed_params}

  defp owner_id_sql(scope, hops, reversed_params) do
    id_path = List.insert_at(hops, -1, :id)

    {id_sql, _column, new_params} = path_sql(scope, id_path, &fetch_column!/2, reversed_params)

    {id_sql, new_params}
  end

  # What a path ends at, read on the row its last hop reads: a derived field computed there, or what
  # the given function picks off the row's mapping - a column, or the columns a loose search reads,
  # the first holding a value.
  defp path_end_sql(scope, {name, select_column}, reversed_params) do
    if Derived.declared?(scope.entity_type, name) do
      derived_sql(scope, name, reversed_params)
    else
      case select_column.(scope.entity_mapping, name) do
        columns when is_list(columns) ->
          {coalesced_sql(scope.row_prefix, columns), List.last(columns), reversed_params}

        column ->
          {column_sql(scope, column), column, reversed_params}
      end
    end
  end

  # A hop of a path is a scalar subquery reading one related row - the first correlated on the row
  # the condition is about, each later one on the hop before it - and the last selects the column
  # the path ends at. A hop that finds no row selects NULL, so a path through an empty relationship,
  # a row that is gone or one the read policy hides reads as a missing value, the way an attribute
  # with none does. Under a statement's policy each hop applies its type's read policy to the row
  # it reads, and inside a policy rule it reads raw.
  defp path_hop_sql(
         scope,
         quoted_prefix,
         entity_type,
         [hop | later_hops],
         leaf,
         hop_index,
         reversed_params
       ) do
    reference =
      scope.mapping
      |> Map.fetch!(entity_type)
      |> reference_column(hop)

    target_type = relationship_target(entity_type, hop)
    target_mapping = Map.fetch!(scope.mapping, target_type)
    number = scope.path_depth + hop_index
    quoted_alias = Mapper.quote_identifier("$p#{number}")

    {selected_sql, column, params_after_select} =
      case later_hops do
        [] ->
          target_type
          |> condition_scope(
            scope.mapping,
            quoted_alias,
            scope.policy,
            number,
            scope.delegation_depth
          )
          |> Map.merge(%{qualified: true, source_depth: scope.source_depth})
          |> path_end_sql(leaf, reversed_params)

        _later_hops ->
          path_hop_sql(
            scope,
            quoted_alias,
            target_type,
            later_hops,
            leaf,
            hop_index + 1,
            reversed_params
          )
      end

    {policy_conditions, new_params} =
      path_policy_conditions(scope, target_type, quoted_alias, number, params_after_select)

    join_sql =
      ~s|#{quoted_alias}."id" = #{quoted_prefix}.#{Mapper.quote_identifier(reference.name)}|

    where_sql = Enum.join([join_sql | policy_conditions], " AND ")

    hop_sql =
      "(SELECT #{selected_sql} FROM #{qualified_table(target_mapping.table)} AS #{quoted_alias} " <>
        "WHERE #{where_sql})"

    {hop_sql, column, new_params}
  end

  # The hop type's read policy, keyed on the hop's alias, nested paths numbered past it and a nested
  # delegation past the enclosing ones.
  defp path_policy_conditions(%{policy: nil}, _hop_type, _quoted_alias, _number, reversed_params),
    do: {[], reversed_params}

  defp path_policy_conditions(scope, hop_type, quoted_alias, number, reversed_params) do
    hop_policy = include_policy(scope.policy, hop_type)

    hop_context =
      hop_type
      |> policy_context(scope.mapping, hop_policy, quoted_alias)
      |> Map.merge(%{delegation_depth: scope.delegation_depth, path_depth: number})

    policy_conditions(hop_policy, hop_context, reversed_params)
  end

  # The SQL reading what a path ends at - the column the given function picks off the mapping of
  # the type its relationships lead to.
  defp path_sql(scope, path, select_column, reversed_params) do
    {hops, [name]} = Enum.split(path, -1)

    path_hop_sql(
      scope,
      scope.row_prefix,
      scope.entity_type,
      hops,
      {name, select_column},
      1,
      reversed_params
    )
  end

  # The row prefix qualifies references to the row a policy is evaluated for. It is the entity's
  # table name at statement level, and the subquery's alias inside an include or a delegation -
  # where the table name would resolve to the outer row for a relationship back to its own type.
  # The delegation depth counts the delegations the policy is nested in, naming each one's alias,
  # and the path depth the path hops, so a path inside it takes aliases no enclosing hop has.
  # Every alias the compiler gives a table begins with a $, which no derived table name begins
  # with, so an alias never names a table the statement also reads.
  defp policy_context(entity_type, mapping, policy, quoted_row_prefix \\ nil)

  defp policy_context(_entity_type, _mapping, nil, _quoted_row_prefix), do: nil

  defp policy_context(entity_type, mapping, policy, quoted_row_prefix) do
    entity_mapping = Map.fetch!(mapping, entity_type)

    %{
      anonymous?: Map.get(policy, :anonymous?, false),
      delegation_depth: 0,
      entity_mapping: entity_mapping,
      entity_type: entity_type,
      mapping: mapping,
      path_depth: 0,
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
      ~s|EXISTS (SELECT 1 FROM #{grant_table(context)} AS "$rg" | <>
        ~s|WHERE "$rg"."user_id" = #{actor_placeholder} | <>
        ~s|AND "$rg"."role" = ANY(#{role_placeholder}) AND #{scope_sql})|

    {condition, new_params}
  end

  # A global role is held without an entity, so the row shape has both scope columns nil -
  # the lookup needs no correlation with the queried row.
  defp grant_scope_sql({:global, _role_modules}, _context, reversed_params) do
    {~s|"$rg"."entity_type" IS NULL AND "$rg"."entity_id" IS NULL|, reversed_params}
  end

  # A rule's own roles are held on the row itself or on its whole type - the lookup matches
  # both shapes, which the store keeps apart by whether its entity_id column is nil.
  defp grant_scope_sql({:own, _role_names}, context, reversed_params) do
    {placeholder, new_params} =
      entity_type_slot(context.entity_type, context, reversed_params)

    entity_sql =
      ~s|("$rg"."entity_id" = #{context.row_prefix}."id" OR "$rg"."entity_id" IS NULL)|

    {~s|"$rg"."entity_type" = #{placeholder} AND #{entity_sql}|, new_params}
  end

  # The grant store's own policy checks a role held on the entity a grant row names, so the
  # lookup keys on the outer row's entity_id column rather than on a relationship reference.
  defp grant_scope_sql({:named, target_type, _role_names}, context, reversed_params) do
    {placeholder, new_params} = entity_type_slot(target_type, context, reversed_params)

    scope_sql =
      ~s|"$rg"."entity_type" = #{placeholder} | <>
        ~s|AND "$rg"."entity_id" = #{context.row_prefix}."entity_id"|

    {scope_sql, new_params}
  end

  defp grant_scope_sql({:type, target_type, _role_names}, context, reversed_params) do
    {placeholder, new_params} = entity_type_slot(target_type, context, reversed_params)

    {~s|"$rg"."entity_type" = #{placeholder} AND "$rg"."entity_id" IS NULL|, new_params}
  end

  # The role is held on the row the chain leads to, named by the id its last reference holds.
  defp grant_scope_sql({:rel, relationship_names, _role_names}, context, reversed_params) do
    {placeholder, params_after_type} =
      context.entity_type
      |> Entity.path_target(relationship_names)
      |> entity_type_slot(context, reversed_params)

    {target_id_sql, new_params} =
      chain_target_id_sql(context, relationship_names, params_after_type)

    scope_sql =
      ~s|"$rg"."entity_type" = #{placeholder} | <>
        ~s|AND "$rg"."entity_id" = #{target_id_sql}|

    {scope_sql, new_params}
  end

  defp grant_table(context) do
    table =
      context.mapping
      |> Map.fetch!(RoleGrant)
      |> Map.fetch!(:table)

    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(table)}"
  end

  defp group_condition([rule_sql]), do: rule_sql

  defp group_condition(rule_sqls) do
    "(" <> Enum.map_join(rule_sqls, " OR ", &"(#{&1})") <> ")"
  end

  # Delegation asks the related entity's policy for the operation the rule names, composed into a
  # correlated EXISTS. The related table takes an alias of its own, so a relationship back to the
  # delegating type keeps the related row apart from the delegating one. An alias only has to
  # differ from the two scopes its subquery reads - its own and the one directly outside - so it
  # is named by depth, and sibling delegations share it. Recursion terminates because delegation
  # cycles are a compile error, so every chain reaches an operation of a type whose rules delegate
  # no further.
  defp delegation_conditions(nil, _context, reversed_params), do: {[], reversed_params}

  defp delegation_conditions(
         {delegated_operation, relationship_names},
         context,
         reversed_params
       ) do
    target_type = Entity.path_target(context.entity_type, relationship_names)
    target_mapping = Map.fetch!(context.mapping, target_type)

    {target_id_sql, params_after_chain} =
      chain_target_id_sql(context, relationship_names, reversed_params)

    target_rules =
      target_type
      |> Policy.build()
      |> Map.get(delegated_operation, [])

    target_policy = %{
      anonymous?: context.anonymous?,
      rules: target_rules
    }

    depth = context.delegation_depth + 1
    quoted_alias = Mapper.quote_identifier("$d#{depth}")

    target_context =
      target_type
      |> policy_context(context.mapping, target_policy, quoted_alias)
      |> Map.merge(%{delegation_depth: depth, path_depth: context.path_depth})

    {target_conditions, new_params} =
      policy_conditions(target_policy, target_context, params_after_chain)

    join_sql = ~s|#{quoted_alias}."id" = #{target_id_sql}|

    inner_sql = Enum.join([join_sql | target_conditions], " AND ")

    condition =
      ~s|EXISTS (SELECT 1 FROM #{qualified_table(target_mapping.table)} AS #{quoted_alias} | <>
        ~s|WHERE #{inner_sql})|

    {[condition], new_params}
  end

  # A rule's own condition is about the row the policy is evaluated for, and reads the rows its paths
  # reach as stored, the way its delegation does - a hop applying a read policy inside a rule could
  # reach that rule again.
  defp rule_condition(rule, context, reversed_params) do
    scope =
      condition_scope(
        context.entity_type,
        context.mapping,
        context.row_prefix,
        nil,
        context.path_depth,
        context.delegation_depth
      )

    {predicate_conditions, params_after_predicates} =
      conditions(rule.predicates, scope, reversed_params)

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

  defp conditions(triples, scope, reversed_params) do
    Enum.map_reduce(triples, reversed_params, fn triple, acc_params ->
      condition(triple, scope, acc_params)
    end)
  end

  # The rows a derived field holding rows embeds for the scope's row, the way an include embeds a
  # relationship's: a set's rows aggregated in the query's order, its bounds applied, or its first
  # row - the rows of the branch an if takes, and none for nil.
  defp rows_include_sql({:if, clauses, then_rows, else_rows}, scope, rows_term, cardinality, acc) do
    {reversed_params, index} = acc
    {condition_sqls, params_after_conditions} = conditions(clauses, scope, reversed_params)

    {then_sql, then_acc} =
      rows_include_sql(then_rows, scope, rows_term, cardinality, {params_after_conditions, index})

    {else_sql, new_acc} = rows_include_sql(else_rows, scope, rows_term, cardinality, then_acc)

    case_sql =
      "CASE WHEN #{Enum.join(condition_sqls, " AND ")} THEN #{then_sql} ELSE #{else_sql} END"

    {case_sql, new_acc}
  end

  defp rows_include_sql({:query, term}, scope, rows_term, cardinality, acc) do
    {reversed_params, index} = acc
    {from_sql, inner_scope, params_after_from} = sourced_from_sql(scope, term, reversed_params)
    {order_sql, params_after_order} = order_clause(term.sort, inner_scope, params_after_from)
    target_mapping = Map.fetch!(scope.mapping, term.entity)
    quoted_wrapper = Mapper.quote_identifier("$i#{index}")

    {nested_pairs, {params_after_nested, next_index}} =
      include_pairs(
        rows_term,
        target_mapping,
        scope.mapping,
        scope.policy,
        quoted_wrapper,
        {params_after_order, index + 1}
      )

    object_sql =
      "jsonb_build_object(#{jsonb_pairs(target_mapping, quoted_wrapper)}#{nested_pairs})"

    rows_sql = "SELECT #{inner_scope.row_prefix}.* #{from_sql}#{order_sql}"

    case cardinality do
      :one ->
        limit = if term.take == 0, do: 0, else: 1
        offset_sql = if term.skip, do: " OFFSET #{term.skip}", else: ""

        row_sql =
          "(SELECT #{object_sql} " <>
            "FROM (#{rows_sql} LIMIT #{limit}#{offset_sql}) AS #{quoted_wrapper})"

        {row_sql, {params_after_nested, next_index}}

      :set ->
        wrapper_scope = %{inner_scope | qualified: true, row_prefix: quoted_wrapper}

        {aggregate_order_sql, new_params} =
          order_clause(term.sort, wrapper_scope, params_after_nested)

        set_sql =
          "(SELECT COALESCE(jsonb_agg(#{object_sql}#{aggregate_order_sql}), '[]'::jsonb) " <>
            "FROM (#{rows_sql}#{bounds_clause(term)}) AS #{quoted_wrapper})"

        {set_sql, {new_params, next_index}}
    end
  end

  defp rows_include_sql({:value, nil}, _scope, _rows_term, :one, acc), do: {"NULL", acc}

  defp rows_include_sql({:value, nil}, _scope, _rows_term, :set, acc), do: {"'[]'::jsonb", acc}

  # Whether the given row is among a derived set's rows for the scope's row: a query's rows, bounded
  # in its order, the rows of the branch an if takes, or none for nil.
  defp rows_membership_sql(
         {:if, clauses, then_rows, else_rows},
         scope,
         quoted_target,
         reversed_params
       ) do
    {condition_sqls, params_after_conditions} = conditions(clauses, scope, reversed_params)

    {then_sql, params_after_then} =
      rows_membership_sql(then_rows, scope, quoted_target, params_after_conditions)

    {else_sql, new_params} =
      rows_membership_sql(else_rows, scope, quoted_target, params_after_then)

    case_sql =
      "CASE WHEN #{Enum.join(condition_sqls, " AND ")} THEN #{then_sql} ELSE #{else_sql} END"

    {case_sql, new_params}
  end

  defp rows_membership_sql({:query, term}, scope, quoted_target, reversed_params) do
    {from_sql, inner_scope, params_after_from} = sourced_from_sql(scope, term, reversed_params)
    bounds_sql = bounds_clause(term)

    {order_sql, new_params} =
      if bounds_sql == "" do
        {"", params_after_from}
      else
        order_clause(term.sort, inner_scope, params_after_from)
      end

    rows_sql = ~s|SELECT #{inner_scope.row_prefix}."id" #{from_sql}#{order_sql}#{bounds_sql}|

    {~s|#{quoted_target}."id" IN (#{rows_sql})|, new_params}
  end

  defp rows_membership_sql({:value, nil}, _scope, _quoted_target, reversed_params) do
    {"FALSE", reversed_params}
  end

  # The type a computed value is read as - an enum as its label, since no enum type in the database
  # holds a derived field's labels.
  defp scalar_sql_type(:boolean), do: "boolean"
  defp scalar_sql_type(:date), do: "date"
  defp scalar_sql_type(:datetime), do: "timestamptz"
  defp scalar_sql_type(:enum), do: "text"
  defp scalar_sql_type(:float), do: "float8"
  defp scalar_sql_type(:integer), do: "int8"
  defp scalar_sql_type(:string), do: "text"
  defp scalar_sql_type(:time), do: "time"
  defp scalar_sql_type(:uuid), do: "uuid"

  # The search key and the sort key of a string attribute, in the order a loose search reads them:
  # the search key holds the whole folded value when the sort key's prefix can't.
  defp search_columns(entity_mapping, name) do
    Enum.map([:search_key, :sort_key], fn kind ->
      Enum.find(entity_mapping.columns, &(&1.source == {kind, name}))
    end)
  end

  # What a search reads: the value for an exact match, its whole folded form for a loose one - on
  # the row, on a row above, or at the end of a path.
  defp search_subject_sql(scope, name, :exact, reversed_params) do
    {subject_sql, _column, new_params} = subject_sql(scope, name, reversed_params)

    {subject_sql, new_params}
  end

  defp search_subject_sql(scope, name, :loose, reversed_params) when is_atom(name) do
    quoted_prefix = if scope.qualified, do: scope.row_prefix
    columns = search_columns(scope.entity_mapping, name)

    {coalesced_sql(quoted_prefix, columns), reversed_params}
  end

  defp search_subject_sql(scope, {:outer, levels, name}, :loose, reversed_params) do
    scope
    |> outer_scope(levels)
    |> search_subject_sql(name, :loose, reversed_params)
  end

  defp search_subject_sql(scope, path, :loose, reversed_params) do
    {path_sql, _column, new_params} = path_sql(scope, path, &search_columns/2, reversed_params)

    {path_sql, new_params}
  end

  # A quantifier's set and the condition its rows are matched to the owner row by - a stored to-many
  # through its join table, an inverse set through the reference or the join table it reverses.
  defp set_membership(owner_type, set_name, mapping, owner_id_sql) do
    case Entity.inverse_relationship(owner_type, set_name) do
      nil ->
        join_table =
          mapping
          |> Map.fetch!(owner_type)
          |> Map.fetch!(:join_tables)
          |> Enum.find(&(&1.relationship == set_name))

        {Entity.related_type(owner_type, set_name), join_membership(join_table, owner_id_sql)}

      inverse ->
        {inverse.target, inverse_membership(inverse, mapping, owner_id_sql)}
    end
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

  # Whether the given row is among the rows a source chain leads to from the scope's row: the last
  # link's rows of every row the links before it reach, so a set before the last is flattened and a
  # row reached twice is one row. A row along the way the read policy hides leads nowhere, and a
  # missing one leads nowhere either.
  defp source_membership_sql(scope, [name], quoted_target, reversed_params) do
    link_membership_sql(scope, name, quoted_target, reversed_params)
  end

  defp source_membership_sql(scope, chain, quoted_target, reversed_params) do
    {earlier_links, [name]} = Enum.split(chain, -1)
    link_type = Derived.path_target(scope.entity_type, earlier_links)
    quoted_alias = Mapper.quote_identifier("$s#{scope.source_depth}_#{length(earlier_links)}")

    {reached_sql, params_after_reached} =
      source_membership_sql(scope, earlier_links, quoted_alias, reversed_params)

    {policy_conditions, params_after_policy} =
      path_policy_conditions(
        scope,
        link_type,
        quoted_alias,
        scope.path_depth,
        params_after_reached
      )

    {link_sql, new_params} =
      link_type
      |> condition_scope(
        scope.mapping,
        quoted_alias,
        scope.policy,
        scope.path_depth,
        scope.delegation_depth
      )
      |> Map.merge(%{qualified: true, source_depth: scope.source_depth})
      |> link_membership_sql(name, quoted_target, params_after_policy)

    where_sql = Enum.join([reached_sql | policy_conditions] ++ [link_sql], " AND ")
    link_table = Map.fetch!(scope.mapping, link_type).table

    exists_sql =
      "EXISTS (SELECT 1 FROM #{qualified_table(link_table)} AS #{quoted_alias} WHERE #{where_sql})"

    {exists_sql, new_params}
  end

  # The scope a quantifier's source is read on: the current row's, or the row's that many out.
  defp source_scope(scope, {:outer, levels, hops}), do: {Enum.at(scope.outer, levels - 1), hops}

  defp source_scope(scope, hops), do: {scope, hops}

  # The FROM and WHERE of a subquery over the rows a derived field's query reads, aliased by how
  # deep it nests: the rows its source leads to from the owner row, readable under the read policy,
  # matching its clauses - inside which the owner is the nearest row above, as a quantifier's row is.
  # Returned with the scope of those rows.
  defp sourced_from_sql(owner_scope, %{source: {_owner_type, chain}} = term, reversed_params) do
    depth = owner_scope.source_depth + 1
    quoted_alias = Mapper.quote_identifier("$s#{depth}")

    {membership_sql, params_after_membership} =
      owner_scope
      |> Map.merge(%{qualified: true, source_depth: depth})
      |> source_membership_sql(chain, quoted_alias, reversed_params)

    {policy_conditions, params_after_policy} =
      path_policy_conditions(
        owner_scope,
        term.entity,
        quoted_alias,
        owner_scope.path_depth,
        params_after_membership
      )

    inner_scope =
      term.entity
      |> condition_scope(
        owner_scope.mapping,
        quoted_alias,
        owner_scope.policy,
        owner_scope.path_depth,
        owner_scope.delegation_depth
      )
      |> Map.merge(%{
        outer: [owner_scope | owner_scope.outer],
        quantifier_depth: owner_scope.quantifier_depth,
        source_depth: depth
      })

    {conditions, new_params} = conditions(term.filter, inner_scope, params_after_policy)

    where_sql = Enum.join([membership_sql | policy_conditions] ++ conditions, " AND ")
    table = Map.fetch!(owner_scope.mapping, term.entity).table

    {"FROM #{qualified_table(table)} AS #{quoted_alias} WHERE #{where_sql}", inner_scope,
     new_params}
  end

  defp bind_placeholder_slot(placeholder_name, type, reversed_params) do
    {"$#{length(reversed_params) + 1}",
     [{:placeholder, placeholder_name, type} | reversed_params]}
  end

  # An included derived field holding a value is the value its definition computes for the parent
  # row. One holding rows embeds its definition's rows, each read with what the definition and the
  # include ask it to embed.
  defp derived_include_expression(scope, name, nil, {reversed_params, index}) do
    {value_sql, _column, new_params} = derived_sql(scope, name, reversed_params)

    {value_sql, {new_params, index}}
  end

  defp derived_include_expression(scope, name, sub_term, acc) do
    rows_term = Derived.rows_term(scope.entity_type, name, sub_term)

    cardinality =
      case List.keyfind(scope.entity_type.__derived__(), name, 0) do
        {^name, [_row_type], _opts} -> :set
        {^name, _row_type, _opts} -> :one
      end

    scope.entity_type
    |> Derived.definition(name)
    |> rows_include_sql(scope, rows_term, cardinality, acc)
  end

  # A derived field holding a value is computed where it is read, from its definition. Its column
  # says how a value compared with it binds - by its declared type, an enum by label - and is
  # nullable.
  defp derived_sql(scope, name, reversed_params) do
    {^name, type, opts} = List.keyfind(scope.entity_type.__derived__(), name, 0)
    column = value_column(type, opts[:values])

    {value_sql, new_params} =
      scope.entity_type
      |> Derived.definition(name)
      |> expression_sql(scope, column, reversed_params)

    {value_sql, column, new_params}
  end

  defp direction_sql(:asc), do: "ASC"
  defp direction_sql(:desc), do: "DESC"

  # A definition's expression, read on the row the scope is about, as a value of the given column's
  # type.
  defp expression_sql({:concat, operands}, scope, column, reversed_params) do
    {operand_sqls, new_params} =
      Enum.map_reduce(operands, reversed_params, &expression_sql(&1, scope, column, &2))

    {"(#{Enum.join(operand_sqls, " || ")})", new_params}
  end

  defp expression_sql({:condition, clauses}, scope, _column, reversed_params) do
    {condition_sqls, new_params} = conditions(clauses, scope, reversed_params)

    {"COALESCE((#{Enum.join(condition_sqls, " AND ")}), false)", new_params}
  end

  defp expression_sql({:if, clauses, then_value, else_value}, scope, column, reversed_params) do
    {condition_sqls, params_after_conditions} = conditions(clauses, scope, reversed_params)

    {then_sql, params_after_then} =
      expression_sql(then_value, scope, column, params_after_conditions)

    {else_sql, new_params} = expression_sql(else_value, scope, column, params_after_then)

    case_sql =
      "CASE WHEN #{Enum.join(condition_sqls, " AND ")} THEN #{then_sql} ELSE #{else_sql} END"

    {case_sql, new_params}
  end

  defp expression_sql({:name, name}, scope, column, reversed_params) do
    {name_sql, name_column, new_params} = subject_sql(scope, name, reversed_params)

    {cast_sql(name_sql, name_column, column), new_params}
  end

  # A count is a correlated subquery over the rows the source leads to. Bounds cap the rows counted,
  # as a counting statement's do.
  defp expression_sql({:query, %{cardinality: :count} = term}, scope, _column, reversed_params) do
    {from_sql, _inner_scope, new_params} = sourced_from_sql(scope, term, reversed_params)
    bounds_sql = bounds_clause(term)

    count_sql =
      if bounds_sql == "" do
        "(SELECT count(*) #{from_sql})"
      else
        quoted_wrapper = Mapper.quote_identifier("$sc#{scope.source_depth + 1}")

        "(SELECT count(*) FROM (SELECT 1 #{from_sql}#{bounds_sql}) AS #{quoted_wrapper})"
      end

    {count_sql, new_params}
  end

  # A slot's type can't be told from a CASE whose branches are all slots, so every literal is cast
  # to the type it stands for.
  defp expression_sql({:value, nil}, _scope, column, reversed_params) do
    {"NULL::#{column.sql_type}", reversed_params}
  end

  defp expression_sql({:value, value}, _scope, column, reversed_params) do
    {placeholder, new_params} = bind_slot(value, column, reversed_params)

    {"#{placeholder}::#{column.sql_type}", new_params}
  end

  defp fold_term(term, :exact), do: term

  defp fold_term(term, :loose), do: SortKey.fold(term)

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

  # A relationship's include is a set aggregated like a to-many or one row like a to-one, differing
  # only in how a related row is matched to the parent row. A derived field's is computed from its
  # definition.
  defp include_expression(
         {name, sub_term},
         parent_type,
         parent_mapping,
         mapping,
         policy,
         parent_prefix,
         acc
       ) do
    if Derived.declared?(parent_type, name) do
      parent_type
      |> condition_scope(mapping, parent_prefix, policy)
      |> Map.put(:qualified, true)
      |> derived_include_expression(name, sub_term, acc)
    else
      case relationship_membership(parent_type, parent_mapping, name, mapping, parent_prefix) do
        {:to_many, membership} ->
          to_many_include_expression(sub_term, membership, mapping, policy, acc)

        {:to_one, match} ->
          to_one_include_expression(sub_term, match, mapping, policy, acc)
      end
    end
  end

  defp include_pairs(term, target_mapping, mapping, policy, quoted_alias, acc) do
    {fragments, new_acc} =
      term.include
      |> Enum.sort_by(fn {entry_name, _sub_term} -> entry_name end)
      |> Enum.map_reduce(acc, fn {entry_name, _sub_term} = entry, inner_acc ->
        {expression, next_acc} =
          include_expression(
            entry,
            term.entity,
            target_mapping,
            mapping,
            policy,
            quoted_alias,
            inner_acc
          )

        {", '#{entry_name}', #{expression}", next_acc}
      end)

    {Enum.join(fragments, ""), new_acc}
  end

  # An include embeds rows of the target type, so every level composes that type's :read policy,
  # whatever rules the statement's own policy holds.
  defp include_policy(nil, _entity_type), do: nil

  defp include_policy(policy, entity_type) do
    %{
      anonymous?: Map.get(policy, :anonymous?, false),
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
          include_expression(
            entry,
            term.entity,
            entity_mapping,
            mapping,
            policy,
            quoted_prefix,
            acc
          )

        {", #{expression} AS #{Mapper.quote_identifier(Atom.to_string(name))}", new_acc}
      end)

    {Enum.join(fragments, ""), new_params}
  end

  # A single inverse's related row is the one whose reference names the parent row.
  defp inverse_match(inverse, mapping, parent_prefix) do
    column = inverse_reference_column(inverse, mapping)

    fn quoted_alias ->
      ~s|#{quoted_alias}.#{Mapper.quote_identifier(column.name)} = #{parent_prefix}."id"|
    end
  end

  # An inverse set's related rows: those whose reference names the parent row when the inverse
  # reverses a to-one, those the related type's join table pairs with the parent row as the target
  # when it reverses a to-many - the pairs read the other way, through the table's target index.
  defp inverse_membership(%{reference?: true} = inverse, mapping, parent_id_sql) do
    column = inverse_reference_column(inverse, mapping)

    fn quoted_target, _quoted_join ->
      ~s|#{quoted_target}.#{Mapper.quote_identifier(column.name)} = #{parent_id_sql}|
    end
  end

  defp inverse_membership(inverse, mapping, parent_id_sql) do
    join_table =
      mapping
      |> Map.fetch!(inverse.target)
      |> Map.fetch!(:join_tables)
      |> Enum.find(&(&1.relationship == inverse.forward))

    fn quoted_target, quoted_join ->
      ~s|#{quoted_target}."id" IN | <>
        ~s|(SELECT #{quoted_join}."source_id" | <>
        "FROM #{qualified_table(join_table.name)} AS #{quoted_join} " <>
        ~s|WHERE #{quoted_join}."target_id" = #{parent_id_sql})|
    end
  end

  defp inverse_reference_column(inverse, mapping) do
    mapping
    |> Map.fetch!(inverse.target)
    |> Map.fetch!(:columns)
    |> Enum.find(&(&1.source == {:relationship, inverse.forward}))
  end

  # A to-many's related rows: those its own join table pairs with the parent row as the source.
  defp join_membership(join_table, parent_id_sql) do
    fn quoted_target, quoted_join ->
      ~s|#{quoted_target}."id" IN | <>
        ~s|(SELECT #{quoted_join}."target_id" | <>
        "FROM #{qualified_table(join_table.name)} AS #{quoted_join} " <>
        ~s|WHERE #{quoted_join}."source_id" = #{parent_id_sql})|
    end
  end

  defp jsonb_pairs(target_mapping, quoted_alias) do
    target_mapping.columns
    |> Enum.reject(&Mapper.derived?/1)
    |> Enum.map_join(", ", fn column ->
      "'#{column.name}', #{quoted_alias}.#{Mapper.quote_identifier(column.name)}"
    end)
  end

  # Whether the given row is among the rows one link of a source leads to from the scope's row: a
  # relationship's related rows, or the rows a derived field's definition holds.
  defp link_membership_sql(scope, name, quoted_target, reversed_params) do
    if Derived.declared?(scope.entity_type, name) do
      scope.entity_type
      |> Derived.definition(name)
      |> rows_membership_sql(scope, quoted_target, reversed_params)
    else
      quoted_join = Mapper.quote_identifier("$sj#{scope.source_depth}")

      membership_sql =
        case relationship_membership(
               scope.entity_type,
               scope.entity_mapping,
               name,
               scope.mapping,
               scope.row_prefix
             ) do
          {:to_many, membership} -> membership.(quoted_target, quoted_join)
          {:to_one, match} -> match.(quoted_target)
        end

      {membership_sql, reversed_params}
    end
  end

  defp maybe_require_value(condition_sql, subject_sql, %{null: true}) do
    "(#{condition_sql} AND #{subject_sql} IS NOT NULL)"
  end

  defp maybe_require_value(condition_sql, _subject_sql, _column), do: condition_sql

  defp null_inclusive(condition_sql, subject_sql, %{null: true}) do
    "(#{condition_sql} OR #{subject_sql} IS NULL)"
  end

  defp null_inclusive(condition_sql, _subject_sql, _column), do: condition_sql

  # A :string ordering whose mapping carries a `<attribute>_$sort` companion
  # orders by the companion first and the original column right after it (ties
  # past the key cap break on the full original bytes), both in the entry's
  # direction. Without a companion the raw column orders alone, and a derived
  # field by the value its definition computes - an enum by its label's position.
  defp order_clause([], _scope, reversed_params), do: {"", reversed_params}

  defp order_clause(entries, scope, reversed_params) do
    {rendered_entries, new_params} =
      Enum.map_reduce(entries, reversed_params, fn {name, direction}, acc_params ->
        {keys_sql, next_params} = order_keys_sql(scope, name, acc_params)

        rendered_entry = Enum.map_join(keys_sql, ", ", &"#{&1} #{direction_sql(direction)}")

        {rendered_entry, next_params}
      end)

    {" ORDER BY " <> Enum.join(rendered_entries, ", "), new_params}
  end

  defp order_keys_sql(scope, name, reversed_params) do
    if Derived.declared?(scope.entity_type, name) do
      {value_sql, column, new_params} = derived_sql(scope, name, reversed_params)

      {[position_sql(value_sql, column)], new_params}
    else
      column = fetch_column!(scope.entity_mapping, name)

      columns =
        case companion_column(scope.entity_mapping, name) do
          nil -> [column]
          companion -> [companion, column]
        end

      {Enum.map(columns, &column_sql(scope, &1)), reversed_params}
    end
  end

  # The scope of the row the given number of levels out, its columns qualified, since the current
  # row's unqualified ones are the innermost table's.
  defp outer_scope(scope, levels) do
    scope.outer
    |> Enum.at(levels - 1)
    |> Map.put(:qualified, true)
  end

  defp companion_column(entity_mapping, name) do
    Enum.find(entity_mapping.columns, &(&1.source == {:sort_key, name}))
  end

  # A computed enum orders by its label's position among the declared labels, since no enum type in
  # the database holds a derived field's labels. Every other value orders by itself.
  defp position_sql(sql, %{source: :derived, type: :enum, values: values}) do
    labels_sql =
      Enum.map_join(values, ", ", fn value ->
        label = Codec.encode_enum_value(value)

        "'#{String.replace(label, "'", "''")}'"
      end)

    "array_position(ARRAY[#{labels_sql}], #{sql})"
  end

  defp position_sql(sql, _column), do: sql

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(table)}"
  end

  # all holds when no related row fails its condition - one the condition is not true of, an
  # unknown comparison against NULL included - so its conditions are wrapped to ask for those.
  defp quantified_conditions(:all, conditions) do
    ["(#{Enum.join(conditions, " AND ")}) IS NOT TRUE"]
  end

  defp quantified_conditions(_quantifier, conditions), do: conditions

  # The rows a quantifier is about and the condition matching one of them to the row its source
  # starts at: a relationship's through the id of the row its to-ones lead to, a derived field's
  # through its definition, read on that row. A derived field's chain nests a level below the
  # scope's, so no alias it takes shadows a row the quantifier's condition is read on.
  defp quantified_set(scope, source, quoted_alias, quoted_join, reversed_params) do
    {source_scope, hops} = source_scope(scope, source)
    {owner_hops, [set_name]} = Enum.split(hops, -1)
    owner_type = Entity.path_target(source_scope.entity_type, owner_hops)

    if Derived.declared?(owner_type, set_name) do
      {membership_sql, new_params} =
        source_scope
        |> Map.merge(%{qualified: true, source_depth: scope.source_depth + 1})
        |> source_membership_sql(hops, quoted_alias, reversed_params)

      {Derived.related_type(owner_type, set_name), membership_sql, new_params}
    else
      {owner_id_sql, new_params} = owner_id_sql(source_scope, owner_hops, reversed_params)

      {target_type, membership} =
        set_membership(owner_type, set_name, source_scope.mapping, owner_id_sql)

      {target_type, membership.(quoted_alias, quoted_join), new_params}
    end
  end

  # A string's sort key - its companion column, read through the path when the string is a related
  # row's - or nil for a value of any other type.
  defp sort_key_sql(scope, name, reversed_params) when is_atom(name) do
    case companion_column(scope.entity_mapping, name) do
      nil -> {nil, reversed_params}
      companion -> {column_sql(scope, companion), reversed_params}
    end
  end

  defp sort_key_sql(scope, {:outer, levels, name}, reversed_params) do
    scope
    |> outer_scope(levels)
    |> sort_key_sql(name, reversed_params)
  end

  defp sort_key_sql(scope, path, reversed_params) do
    {hops, [name]} = Enum.split(path, -1)
    end_type = Entity.path_target(scope.entity_type, hops)
    end_mapping = Map.fetch!(scope.mapping, end_type)

    if companion_column(end_mapping, name) do
      {key_sql, _companion, new_params} =
        path_sql(scope, path, &companion_column/2, reversed_params)

      {key_sql, new_params}
    else
      {nil, reversed_params}
    end
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
    effective_limit = if term.take == 0, do: 0, else: 1
    offset_sql = if term.skip, do: " OFFSET #{term.skip}", else: ""

    "SELECT #{column_list(entity_mapping)}#{include_sql} " <>
      "FROM #{qualified_table(entity_mapping.table)}" <>
      where_sql <> order_sql <> " LIMIT #{effective_limit}" <> offset_sql
  end

  defp statement(term, entity_mapping, where_sql, order_sql, include_sql) do
    "SELECT #{column_list(entity_mapping)}#{include_sql} " <>
      "FROM #{qualified_table(entity_mapping.table)}" <>
      where_sql <> order_sql <> bounds_clause(term)
  end

  # What a condition compares, and the column that says how its values bind: an attribute of the
  # row, a derived field computed from its definition, or what a path reads - which can always be
  # missing, whatever the column at its end declares, so its column reads as nullable.
  defp subject_sql(scope, name, reversed_params) when is_atom(name) do
    if Derived.declared?(scope.entity_type, name) do
      derived_sql(scope, name, reversed_params)
    else
      column = fetch_column!(scope.entity_mapping, name)

      {column_sql(scope, column), column, reversed_params}
    end
  end

  # A name of a row above is read on that row's scope, qualified with its alias, since the current
  # row's unqualified columns are the innermost table's.
  defp subject_sql(scope, {:outer, levels, name}, reversed_params) do
    scope
    |> outer_scope(levels)
    |> subject_sql(name, reversed_params)
  end

  defp subject_sql(scope, path, reversed_params) do
    {path_sql, column, new_params} = path_sql(scope, path, &fetch_column!/2, reversed_params)

    {path_sql, Map.put(column, :null, true), new_params}
  end

  defp to_many_include_expression(sub_term, membership, mapping, policy, {reversed_params, index}) do
    target_mapping = Map.fetch!(mapping, sub_term.entity)
    quoted_wrapper = Mapper.quote_identifier("$i#{index}")
    quoted_join = Mapper.quote_identifier("$j#{index}")
    quoted_target = Mapper.quote_identifier("$t#{index}")

    filter_scope = condition_scope(sub_term.entity, mapping, quoted_target, policy)

    wrapper_scope =
      sub_term.entity
      |> condition_scope(mapping, quoted_wrapper, policy)
      |> Map.put(:qualified, true)

    {conditions, filtered_params} = conditions(sub_term.filter, filter_scope, reversed_params)

    target_policy = include_policy(policy, sub_term.entity)

    {policy_conditions, policied_params} =
      policy_conditions(
        target_policy,
        policy_context(sub_term.entity, mapping, target_policy, quoted_target),
        filtered_params
      )

    filter_sql = Enum.map_join(conditions ++ policy_conditions, "", &(" AND " <> &1))

    {nested_pairs, {params_after_nested, next_index}} =
      include_pairs(
        sub_term,
        target_mapping,
        mapping,
        policy,
        quoted_wrapper,
        {policied_params, index + 1}
      )

    {order_sql, params_after_order} =
      order_clause(sub_term.sort, filter_scope, params_after_nested)

    {aggregate_order_sql, new_params} =
      order_clause(sub_term.sort, wrapper_scope, params_after_order)

    # The membership condition is a nested subselect or a plain comparison (not a
    # join) so that only the target table is in scope where the sub-term's filter
    # and ordering render their unqualified identifiers - a join would make target
    # columns named like the join-table columns (source_id/target_id) ambiguous.
    inner_sql =
      "SELECT #{quoted_target}.* " <>
        "FROM #{qualified_table(target_mapping.table)} AS #{quoted_target} " <>
        "WHERE #{membership.(quoted_target, quoted_join)}" <>
        filter_sql <>
        order_sql <>
        bounds_clause(sub_term)

    expression =
      "(SELECT COALESCE(jsonb_agg(jsonb_build_object(#{jsonb_pairs(target_mapping, quoted_wrapper)}#{nested_pairs})" <>
        aggregate_order_sql <>
        "), '[]'::jsonb) FROM (#{inner_sql}) AS #{quoted_wrapper})"

    {expression, {new_params, next_index}}
  end

  defp to_one_include_expression(sub_term, match, mapping, policy, {reversed_params, index}) do
    target_mapping = Map.fetch!(mapping, sub_term.entity)
    quoted_alias = Mapper.quote_identifier("$i#{index}")

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
        "WHERE #{match.(quoted_alias)}" <>
        policy_sql <> ")"

    {expression, new_acc}
  end

  # The column a computed value binds as: its type, its labels for an enum, and nullable - a value
  # computed from others can be missing.
  defp value_column(type, values) do
    %{null: true, source: :derived, sql_type: scalar_sql_type(type), type: type, values: values}
  end

  defp where_clause([]), do: ""

  defp where_clause(conditions), do: " WHERE " <> Enum.join(conditions, " AND ")
end
