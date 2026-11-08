defmodule Hologram.Query.Interpreter do
  @moduledoc false

  # The reference implementation of the query kernel: the locked operator set evaluated over
  # plain Elixir data rather than compiled to SQL - comparisons and memberships, joined by `and`
  # (every clause holds) and by `or` (a disjunction holds when one of its alternatives does), and
  # quantifiers (`any`, `none` and `all` of a related set's rows matching a condition).
  #
  # It exists to be proven identical to the database executor in ExUnit, over the same rows -
  # which is what lets the client's hand-written JavaScript kernel be proven identical in turn,
  # against this rather than against a database. Two implementations of a small frozen surface,
  # each pinned to the one before it.
  #
  # Never bundled. Nothing a client can reach calls it, and the client would gain nothing by
  # running it: it reads plain Elixir terms, where the browser holds the wire's own values.

  alias Hologram.DB.SortKey
  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.MisuseError
  alias Hologram.Query
  alias Hologram.Query.Ordering

  @quantifiers [:all, :any, :none]

  @doc """
  Runs the given normalized query term over the given rows and returns what the database would
  return for it - a list of entity structs, one struct or nil for a single-result query, an
  integer for a counting one.

  The rows are the client's whole database rather than a table: `:rows` maps each entity type to
  its rows by id, and `:facts` pairs the ids a to-many relationship holds. A query reads the
  table of its own entity type and reaches the rest through what it includes.

  A path in a filter reads the row its relationships lead to out of the same rows - its reference
  field names the row, looked up in the related type's table - and reads as nil when a reference
  is empty or names a row the database does not hold, the meaning a missing value has everywhere
  else.

  A quantifier reads the rows of a related set out of the same rows - the ones the pairs name, the
  ones whose reference names the row, or the ones a derived field holding rows holds - reached
  through the links of its source before it, the last link's rows of every row they reach, each
  once, and no rows when they reach none. Its condition is matched against each related row, a
  name of a row above read on that row.

  A derived field holding a value is computed from its definition wherever its name is read - a
  predicate's side, a path's end, a sort key - the way the database computes it: `<>` is nil when
  an operand is, an `if` takes its else branch when its condition does not hold, a condition is
  true or false, never nil, and an integer a float field reads is widened. A count counts the rows
  its source leads to from the row - the last link's rows of every row the links before it reach,
  each once - matched to its clauses with the row as the row above them, its bounds applied. A
  derived field holding rows holds its query's rows in its order with its bounds applied, the rows
  of the branch an `if` takes, or none for nil. A derived enum compares and orders by its value's
  position among the declared ones. An included derived field holds its value, or its rows - a
  list, or one row or nil - each row embedding what its definition and the include ask for.

  `:actor_user_id` in the options is who is asking, for the predicates that name the acting user.
  An anonymous one matches nothing, the way an actor-referencing statement matches nothing when
  there is no actor to compare against. `:bindings` gives the values of the term's placeholders, every
  one of which the term names, and none of which may be nil - neither as a value nor as an element
  of a list - which is what the database refuses one for.

  Raises Hologram.MisuseError on a missing or nil binding.
  """
  @spec run(Query.t(), %{atom => any}, keyword) :: list(struct) | struct | integer | nil
  def run(term, database, opts \\ []) do
    scope = match_scope(term, database, opts)

    rows =
      database
      |> table(term.entity)
      |> Enum.filter(&matches?(&1, term.filter, scope))

    case term.cardinality do
      # A count counts what the query evaluates to, so the bounds apply before it is taken -
      # and never the order, which cannot change how many there are. A counting query carries no
      # includes either: an embedded entity cannot change how many there are of what holds it.
      :count ->
        rows
        |> bound(term)
        |> length()

      :one ->
        rows
        |> arrange(term, scope)
        |> List.first()
        |> embed(term, database, opts)

      :set ->
        rows
        |> arrange(term, scope)
        |> Enum.map(&embed(&1, term, database, opts))
    end
  end

  defp arrange(rows, term, scope) do
    rows
    |> Ordering.sort(term.sort, term.entity, &read(&1, &2, scope))
    |> bound(term)
  end

  defp bound(rows, term) do
    rows
    |> Enum.drop(term.skip || 0)
    |> take(term.take)
  end

  # The rows a source chain leads to from the row: the last link's rows of every row the links
  # before it reach, each row once however many paths reach it.
  defp chain_rows(row, chain, scope) do
    Enum.reduce(chain, [row], fn name, rows ->
      rows
      |> Enum.flat_map(&link_rows(&1, name, scope))
      |> Enum.uniq_by(& &1.id)
    end)
  end

  # The rows a definition of a derived field holding rows holds for the row: a query's rows in its
  # order with its bounds applied, only the first for one row, the rows of the branch an if takes,
  # or none for nil.
  defp definition_rows({:if, clauses, then_rows, else_rows}, row, scope) do
    if matches?(row, clauses, row_scope(row, clauses, scope)) do
      definition_rows(then_rows, row, scope)
    else
      definition_rows(else_rows, row, scope)
    end
  end

  defp definition_rows({:query, term}, row, scope) do
    rows =
      row
      |> sourced_rows(term, scope)
      |> arrange(term, scope)

    if term.cardinality == :one, do: Enum.take(rows, 1), else: rows
  end

  defp definition_rows({:value, nil}, _row, _scope), do: []

  defp derived_rows(row, name, scope) do
    row.__struct__
    |> Derived.definition(name)
    |> definition_rows(row, scope)
  end

  # A derived field holding a value, computed from its definition on the row - an integer a float
  # field reads widened, the way the database casts it.
  defp derived_value(row, name, scope) do
    entity_type = row.__struct__
    {^name, type, _opts} = List.keyfind(entity_type.__derived__(), name, 0)

    value =
      entity_type
      |> Derived.definition(name)
      |> evaluated(row, scope)

    if type == :float and is_integer(value), do: value * 1.0, else: value
  end

  # A relationship the query asked for is filled from the rest of the database - a to-one by
  # following the id its row carries, a to-many by reading the pairs. A derived field it asked for is
  # computed from its definition. What the query did not ask for keeps the sentinel saying so, which
  # is a different answer from an empty one.
  defp embed(nil, _term, _database, _opts), do: nil

  defp embed(row, term, database, opts) do
    Enum.reduce(term.include, row, fn {name, sub_term}, embedded ->
      value =
        if Derived.declared?(term.entity, name) do
          embedded_derived_value(row, name, sub_term, database, opts)
        else
          kind = relationship_kind(term.entity, name)

          embedded_value(row, name, kind, sub_term, database, opts)
        end

      Map.put(embedded, name, value)
    end)
  end

  # An included derived field holding a value is the value its definition computes for the row. One
  # holding rows holds its definition's rows - a list, or one row or nil - each row embedding what
  # the definition and the include ask for.
  defp embedded_derived_value(row, name, nil, database, opts) do
    derived_value(row, name, embedding_scope(row, database, opts))
  end

  defp embedded_derived_value(row, name, sub_term, database, opts) do
    entity_type = row.__struct__
    rows_term = Derived.rows_term(entity_type, name, sub_term)

    rows =
      row
      |> derived_rows(name, embedding_scope(row, database, opts))
      |> Enum.map(&embed(&1, rows_term, database, opts))

    case List.keyfind(entity_type.__derived__(), name, 0) do
      {^name, [_row_type], _opts} -> rows
      {^name, _row_type, _opts} -> List.first(rows)
    end
  end

  defp embedded_set(rows, sub_term, database, opts) do
    scope = match_scope(sub_term, database, opts)

    rows
    |> Enum.filter(&matches?(&1, sub_term.filter, scope))
    |> arrange(sub_term, scope)
    |> Enum.map(&embed(&1, sub_term, database, opts))
  end

  defp embedded_value(row, name, :to_one, sub_term, database, opts) do
    reference = Map.fetch!(row, reference_field(name))

    database
    |> table(sub_term.entity)
    |> Enum.find(&(&1.id == reference))
    |> embed(sub_term, database, opts)
  end

  # A to-many is the rows the pairs name, put through the clauses the include carries - a set of
  # its own, filtered, ordered and bounded like any other. A pair naming a row the database does
  # not hold is passed over: a fill arrives in pieces, and a parent can be told about a child
  # that has not landed yet.
  defp embedded_value(row, name, :to_many, sub_term, database, opts) do
    row
    |> paired_rows(name, sub_term.entity, database)
    |> embedded_set(sub_term, database, opts)
  end

  # An inverse is read from where the relationship it reverses is stored: the related rows whose
  # reference names the row, or the ones whose pairs name it as the target. A row whose reference
  # is nil names no row, so it belongs to no inverse. A single inverse is the one related row - the
  # first by id should two ever claim it, which the unique index keeps from happening.
  defp embedded_value(
         row,
         _name,
         {:inverse, %{to_many?: true} = inverse},
         sub_term,
         database,
         opts
       ) do
    row
    |> inverse_rows(inverse, database)
    |> embedded_set(sub_term, database, opts)
  end

  defp embedded_value(row, _name, {:inverse, inverse}, sub_term, database, opts) do
    row
    |> inverse_rows(inverse, database)
    |> Enum.sort_by(& &1.id)
    |> List.first()
    |> embed(sub_term, database, opts)
  end

  # Where a row's derived field is read while it is embedded: on the row, with no row above it.
  defp embedding_scope(row, database, opts) do
    %{database: database, opts: opts, outer: [], ranks: %{}, types: [row.__struct__]}
  end

  defp equal?(%Date{} = left, %Date{} = right), do: Date.compare(left, right) == :eq

  defp equal?(%DateTime{} = left, %DateTime{} = right) do
    DateTime.compare(left, right) == :eq
  end

  defp equal?(%Time{} = left, %Time{} = right), do: Time.compare(left, right) == :eq

  defp equal?(left, right), do: left == right

  # A definition's expression on the row: strings joined, nil when one of them is, an if's branch,
  # whether a condition holds, a name of the row, the number of rows a count reads, or a value.
  defp evaluated({:concat, operands}, row, scope) do
    values = Enum.map(operands, &evaluated(&1, row, scope))

    if Enum.any?(values, &is_nil/1), do: nil, else: Enum.join(values)
  end

  defp evaluated({:condition, clauses}, row, scope) do
    matches?(row, clauses, row_scope(row, clauses, scope))
  end

  defp evaluated({:if, clauses, then_value, else_value}, row, scope) do
    if matches?(row, clauses, row_scope(row, clauses, scope)) do
      evaluated(then_value, row, scope)
    else
      evaluated(else_value, row, scope)
    end
  end

  defp evaluated({:name, name}, row, scope), do: read(row, name, row_scope(row, [], scope))

  defp evaluated({:query, %{cardinality: :count} = term}, row, scope) do
    row
    |> sourced_rows(term, scope)
    |> bound(term)
    |> length()
  end

  defp evaluated({:value, value}, _row, _scope), do: value

  defp inverse_rows(row, %{reference?: true} = inverse, database) do
    reference_field = reference_field(inverse.forward)

    database
    |> table(inverse.target)
    |> Enum.filter(&(Map.fetch!(&1, reference_field) == row.id))
  end

  defp inverse_rows(row, inverse, database) do
    targets = table(database, inverse.target)

    database.facts
    |> Enum.filter(fn {{type, relationship, _source_id}, target_ids} ->
      type == inverse.target and relationship == inverse.forward and row.id in target_ids
    end)
    |> Enum.map(fn {{_type, _relationship, source_id}, _target_ids} ->
      Enum.find(targets, &(&1.id == source_id))
    end)
    |> Enum.reject(&is_nil/1)
  end

  # The left names of a clause list's own predicates, a disjunction's alternatives included - a
  # quantifier's condition is about another row.
  defp level_names(clauses) do
    Enum.flat_map(clauses, fn
      {:or, alternatives} -> Enum.flat_map(alternatives, &level_names/1)
      {quantifier, {_source, _clauses}} when quantifier in @quantifiers -> []
      {name, _operator, _operand} -> [name]
    end)
  end

  # The rows one link of a source leads to from the row: the related row a to-one names, if there is
  # one, or the rows of a set.
  defp link_rows(row, name, scope) do
    entity_type = row.__struct__

    if not Derived.declared?(entity_type, name) and
         relationship_kind(entity_type, name) == :to_one do
      row
      |> related_row([name], scope.database)
      |> List.wrap()
    else
      set_rows(row, name, scope)
    end
  end

  # What matching a term's filter reads besides the row: the rest of the database, which a path
  # follows into, the options a predicate resolves its operands by, the ranks its enums compare
  # by - and inside a quantifier's condition the rows above the related row with their types,
  # nearest first, for the names that reach them.
  defp match_scope(term, database, opts) do
    types = [term.entity]

    %{
      database: database,
      opts: opts,
      outer: [],
      ranks: predicate_ranks(types, term.filter),
      types: types
    }
  end

  defp matches?(row, filter, scope) do
    Enum.all?(filter, &matches_clause?(row, &1, scope))
  end

  # A visitor has no acting user, and each predicate naming one answers false on its own - so a
  # disjunction needs no case for it: the alternative asking about nobody fails, and the others
  # still answer.
  defp matches_clause?(row, {:or, alternatives}, scope) do
    Enum.any?(alternatives, &matches?(row, &1, scope))
  end

  # The condition is matched against each related row, with the row the quantifier is about as the
  # first row above it.
  defp matches_clause?(row, {quantifier, {source, clauses}}, scope)
       when quantifier in @quantifiers do
    {source_row, hops} = source_row(row, source, scope)
    related_rows = chain_rows(source_row, hops, scope)

    types = [Derived.path_target(source_row.__struct__, hops) | scope.types]

    inner_scope = %{
      scope
      | outer: [row | scope.outer],
        ranks: predicate_ranks(types, clauses),
        types: types
    }

    holds? = &matches?(&1, clauses, inner_scope)

    case quantifier do
      :all -> Enum.all?(related_rows, holds?)
      :any -> Enum.any?(related_rows, holds?)
      :none -> not Enum.any?(related_rows, holds?)
    end
  end

  defp matches_clause?(row, triple, scope), do: matches_predicate?(row, triple, scope)

  # Another attribute of the same row, or one a path reaches, is read the way the predicate's own
  # side is, and compared by the predicate's attribute's ranks - two enums compare only when they
  # declare the same list, so one serves both.
  defp matches_predicate?(row, {name, operator, {:attribute, other}}, scope) do
    satisfies?(
      operator,
      read(row, name, scope),
      read(row, other, scope),
      Map.get(scope.ranks, name)
    )
  end

  defp matches_predicate?(row, {name, operator, operand}, scope) do
    ranks_for_key = Map.get(scope.ranks, name)

    case resolve(operand, scope.opts, ranks_for_key) do
      # The acting user is nobody, so a predicate asking about them is asking about nobody -
      # which no row answers, the way an actor-referencing statement is elided for a visitor
      # rather than run against a null.
      :no_actor -> false
      value -> satisfies?(operator, read(row, name, scope), value, ranks_for_key)
    end
  end

  # The rows a to-many's pairs name, of the given type. A pair naming a row the database does not
  # hold is passed over: a fill arrives in pieces, and a parent can be told about a child that has
  # not landed yet.
  defp paired_rows(row, name, target_type, database) do
    targets = table(database, target_type)

    database.facts
    |> Map.get({row.__struct__, name, row.id}, [])
    |> Enum.map(fn target_id -> Enum.find(targets, &(&1.id == target_id)) end)
    |> Enum.reject(&is_nil/1)
  end

  # The ranks a clause list's own predicates compare by, keyed by the name each predicate is written
  # with - an attribute or a path, whose ranks are those of the attribute it ends at, on the row the
  # name is read on - the ones inside a disjunction's alternatives included. A quantifier's
  # condition is matched with ranks of its own.
  defp predicate_ranks(types, clauses) do
    clauses
    |> level_names()
    |> Enum.uniq()
    |> Enum.flat_map(fn name ->
      {subject_type, subject_name} = subject(types, name)

      subject_type
      |> Ordering.enum_ranks([subject_name])
      |> Enum.map(fn {_subject_name, ranks} -> {name, ranks} end)
    end)
    |> Map.new()
  end

  # A path reads the attribute of the row its relationships lead to, and nil at the first reference
  # that is empty or names a row the database does not hold - a fill arrives in pieces, so a row a
  # reference names may not have landed yet. A name of a row above is read on that row.
  defp read(_row, {:outer, levels, name}, scope) do
    scope.outer
    |> Enum.at(levels - 1)
    |> read(name, scope)
  end

  defp read(row, path, scope) when is_list(path) do
    {relationship_names, [name]} = Enum.split(path, -1)

    case related_row(row, relationship_names, scope.database) do
      nil -> nil
      related -> read(related, name, scope)
    end
  end

  defp read(row, name, scope) do
    if Derived.declared?(row.__struct__, name) do
      derived_value(row, name, scope)
    else
      Map.fetch!(row, name)
    end
  end

  defp resolve({:actor}, opts, _ranks_for_key) do
    Keyword.get(opts, :actor_user_id) || :no_actor
  end

  defp resolve({:placeholder, name}, opts, ranks_for_key) do
    bindings = Keyword.get(opts, :bindings, %{})

    case Map.fetch(bindings, name) do
      :error ->
        raise MisuseError, message: "missing value for placeholder #{inspect(name)}"

      {:ok, value} ->
        value
        |> validate_binding!(name)
        |> validate_declared_value!(name, ranks_for_key)
    end
  end

  defp resolve(operand, opts, ranks_for_key) when is_list(operand) do
    Enum.map(operand, &resolve(&1, opts, ranks_for_key))
  end

  defp resolve(operand, _opts, _ranks_for_key), do: operand

  # Nil is a value like any other to the equality family - an unset attribute is unequal to a
  # set one, and a list may name it - while an ordering line has no place to put one, so a
  # comparison passes over what is not there.
  defp satisfies?(:!=, value, operand, _ranks), do: not equal?(value, operand)

  defp satisfies?(:==, value, operand, _ranks), do: equal?(value, operand)

  defp satisfies?(:in, value, operands, _ranks), do: Enum.any?(operands, &equal?(value, &1))

  defp satisfies?(:not_in, value, operands, _ranks) do
    not Enum.any?(operands, &equal?(value, &1))
  end

  defp satisfies?(_operator, nil, _operand, _ranks), do: false

  # Only an attribute operand can be missing here - a literal nil ordering operand is refused when
  # the query is built, and a placeholder never binds nil.
  defp satisfies?(_operator, _value, nil, _ranks), do: false

  # An exact search compares the bytes, a loose one the folded forms - case, accents and the letters
  # a sort key spells out folded on both sides.
  defp satisfies?(:contains, value, term, _ranks) do
    value
    |> SortKey.fold()
    |> String.contains?(SortKey.fold(term))
  end

  defp satisfies?(:contains_exact, value, term, _ranks), do: String.contains?(value, term)

  defp satisfies?(:starts_with, value, term, _ranks) do
    value
    |> SortKey.fold()
    |> String.starts_with?(SortKey.fold(term))
  end

  defp satisfies?(:starts_with_exact, value, term, _ranks), do: String.starts_with?(value, term)

  defp satisfies?(:<, value, operand, ranks) do
    Ordering.compare(value, operand, ranks) == :lt
  end

  defp satisfies?(:<=, value, operand, ranks) do
    Ordering.compare(value, operand, ranks) in [:eq, :lt]
  end

  defp satisfies?(:>, value, operand, ranks) do
    Ordering.compare(value, operand, ranks) == :gt
  end

  defp satisfies?(:>=, value, operand, ranks) do
    Ordering.compare(value, operand, ranks) in [:eq, :gt]
  end

  # The rows of a set - a to-many's pairs, an inverse set's related rows, or the rows a derived field
  # holds.
  defp set_rows(row, name, scope) do
    entity_type = row.__struct__

    if Derived.declared?(entity_type, name) do
      derived_rows(row, name, scope)
    else
      case relationship_kind(entity_type, name) do
        {:inverse, inverse} ->
          inverse_rows(row, inverse, scope.database)

        :to_many ->
          paired_rows(row, name, Entity.related_type(entity_type, name), scope.database)
      end
    end
  end

  # The reference field's atom is one the entity's own struct defines, so it is always there to
  # be found rather than invented here.
  defp reference_field(name), do: String.to_existing_atom("#{name}_id")

  defp related_row(row, [], _database), do: row

  defp related_row(row, [relationship_name | later_names], database) do
    target_type = Entity.relationship_target(row.__struct__, relationship_name)
    target_id = Map.fetch!(row, reference_field(relationship_name))

    related =
      database.rows
      |> Map.get(target_type, %{})
      |> Map.get(target_id)

    if related, do: related_row(related, later_names, database), else: nil
  end

  defp relationship_kind(entity_type, name) do
    inverse = Entity.inverse_relationship(entity_type, name)
    relationship = List.keyfind(entity_type.__relationships__(), name, 0)

    cond do
      inverse -> {:inverse, inverse}
      match?({_name, [_target], _opts}, relationship) -> :to_many
      true -> :to_one
    end
  end

  # Where a definition's own names and clauses are read: on the row, with no row above it.
  defp row_scope(row, clauses, scope) do
    types = [row.__struct__]

    %{scope | outer: [], ranks: predicate_ranks(types, clauses), types: types}
  end

  # The row a quantifier's source is read on - the row the quantifier is about, or one above it.
  defp source_row(_row, {:outer, levels, hops}, scope),
    do: {Enum.at(scope.outer, levels - 1), hops}

  defp source_row(row, hops, _scope), do: {row, hops}

  # The rows a derived field's query reads off the owner row, matched to its clauses with the owner
  # as the row above them.
  defp sourced_rows(owner, %{source: {_owner_type, chain}} = term, scope) do
    types = [term.entity, owner.__struct__]

    inner_scope = %{
      scope
      | outer: [owner],
        ranks: predicate_ranks(types, term.filter),
        types: types
    }

    owner
    |> chain_rows(chain, scope)
    |> Enum.filter(&matches?(&1, term.filter, inner_scope))
  end

  # Where a name is declared: an attribute on the type of the row it is read on, a path's last name
  # on the type its relationships lead to from there.
  defp subject(types, {:outer, levels, name}), do: subject([Enum.at(types, levels)], name)

  defp subject([entity_type | _types_above], path) when is_list(path) do
    {relationship_names, [name]} = Enum.split(path, -1)

    {Entity.path_target(entity_type, relationship_names), name}
  end

  defp subject([entity_type | _types_above], name), do: {entity_type, name}

  defp table(database, entity_type) do
    database.rows
    |> Map.get(entity_type, %{})
    |> Map.values()
  end

  defp take(rows, nil), do: rows

  defp take(rows, count), do: Enum.take(rows, count)

  # The values the rank map holds, back in the order the entity declares them - the cold path of
  # a refusal, so the sort costs nothing anything else pays for.
  defp declared_values(ranks_for_key) do
    ranks_for_key
    |> Enum.sort_by(fn {_value, index} -> index end)
    |> Enum.map(fn {value, _index} -> value end)
  end

  # A binding on an enum attribute is one of the values that attribute declares, refused in the
  # words the database executor refuses it in - QueryRunner validates every binding against the
  # attribute before a statement is built, so an undeclared label never reaches Postgres on that
  # tier either. A list bound as a whole is left to the runner alone.
  defp validate_declared_value!(value, _name, nil), do: value

  defp validate_declared_value!(values, _name, _ranks_for_key) when is_list(values), do: values

  defp validate_declared_value!(value, name, ranks_for_key) do
    if Map.has_key?(ranks_for_key, value) do
      value
    else
      raise MisuseError,
        message:
          "invalid value #{inspect(value)} for placeholder #{inspect(name)} - expected one of #{inspect(declared_values(ranks_for_key))}"
    end
  end

  # A binding carries no nil anywhere, which is what the database refuses it for - and identity
  # with the database covers what each REFUSES, not only what each answers. A predicate about the
  # rows that have no value is written as one, in the query, where the operator can be chosen to
  # suit. A LITERAL list may still name nil: it is part of a term rather than a value handed to
  # one, so it says what it means on its face.
  defp validate_binding!(nil, name) do
    raise MisuseError,
      message:
        "nil value for placeholder #{inspect(name)} - use an explicit nil predicate instead"
  end

  defp validate_binding!(values, name) when is_list(values) do
    if Enum.any?(values, &is_nil/1) do
      raise MisuseError,
        message:
          "nil element in the list for placeholder #{inspect(name)} - use an explicit nil predicate instead"
    end

    values
  end

  defp validate_binding!(value, _name), do: value
end
