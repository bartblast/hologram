defmodule Hologram.Policy.Evaluator do
  @moduledoc false

  # In-memory evaluation of compiled policy rules against entity structs. Predicates are
  # evaluated here, while grant references and delegations are resolved by the checker
  # function the caller injects - they need the grant store and the related rows, which
  # this module deliberately knows nothing about.

  alias Hologram.DB.SortKey
  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Query.Stage

  @ordering_operators [:<, :<=, :>, :>=]

  @quantifiers [:all, :any, :none]

  @search_operators [:contains, :contains_exact, :starts_with, :starts_with_exact]

  @doc """
  Returns true when the given operation's compiled policy grants it for the given entity struct, or false otherwise.

  An operation with no rules grants nothing, which is what makes the default deny.
  """
  @spec grants?(
          %{Entity.operation() => list(map)},
          Entity.operation(),
          struct,
          String.t() | nil,
          fun
        ) ::
          boolean
  def grants?(policy, operation, entity, actor_user_id, checker) do
    policy
    |> Map.get(operation, [])
    |> Enum.any?(&rule_matches?(&1, entity, actor_user_id, checker))
  end

  @doc """
  Returns true when the given compiled rule grants its operation for the given entity struct, or false otherwise.

  Every predicate clause must hold - a disjunction when any of its alternatives does - one grant
  reference must be held, and the related entity must grant the operation the delegation names.
  Predicate values compare as they do in the database: nil is a regular value for equality and
  membership, while ordering comparisons never match it. An attribute operand reads the row's other
  attribute, compared the way a literal is. A path, as a predicate's name or an attribute operand,
  reads its last name off the row its relationships lead to, and reads nil when they lead nowhere -
  so `!=` and `not in` hold for a path that ends nowhere, and an ordering comparison does not.

  A derived field is its definition written in place, computed over the row it is read on - the
  rule's row, or the row a path leads to - its paths read the way the rule's own are: `<>` is nil
  when an operand is, an `if` takes its else branch when its condition does not hold, a condition
  is true or false, never nil. A derived enum
  compares by its value's position among the declared ones. A policy condition reads no derived
  field reading a related set, which the build refuses.

  A quantifier holds when its condition holds for any, none or every row of the set its source
  leads to - all and none hold over an empty set, any does not. Each related row is matched with the
  rows above it, so a name of a row above, `{:outer, levels, name}`, reads the row that many
  quantifiers out, and a source read on a row above starts there.

  For an anonymous session a user_id() predicate is false, whichever way it points, and a grant
  reference is held by nobody - the actor is nobody rather than nil, since a nil actor would make
  rows with a missing reference match everyone. So a conjunction naming the actor fails, and a
  disjunction answers through its other alternatives: `author_id == user_id() or shared == true`
  still grants a visitor the shared rows. An any naming the actor answers through what is left of
  its condition, and a none or an all whose condition names the actor anywhere is false, since it
  asks about nobody. A delegating rule is evaluated as any other, because the entity type it
  delegates to answers its own actor-referencing rules the same way.

  Grant references, delegations and the rows a path reads are resolved by the given checker
  function, called as checker.(requirement, entity, actor user id). For the rule's grant reference
  or a {:via, operation, chain} tuple - the chain of to-one relationships followed to the related
  row - it returns a boolean. For a {:related, relationship names} tuple it returns the row those
  relationships lead to, or nil when one of them is empty or names a row that is gone. For a
  {:set, relationship names} tuple it returns the rows of the set they lead to, each once - asked
  as {:set, relationship names, :whole} when a row joining the set could turn the grant into a
  refusal: a none or an all whose truth helps the rule, an any whose truth hurts it.
  """
  @spec rule_matches?(map, struct, String.t() | nil, fun) :: boolean
  def rule_matches?(rule, entity, actor_user_id, checker) do
    predicates_hold?(rule.predicates, [entity], actor_user_id, checker, :positive) and
      to_holds?(rule.to, entity, actor_user_id, checker) and
      via_holds?(rule.via, entity, actor_user_id, checker)
  end

  # The rows a clause is read on: the row it is about first, then each row above it, nearest first
  # - the rule's row alone outside any quantifier. The polarity says whether the clause holding
  # helps the rule (:positive) or hurts it (:negative), inside a none.
  defp clause_holds?({:or, alternatives}, rows, actor_user_id, checker, polarity) do
    Enum.any?(alternatives, &predicates_hold?(&1, rows, actor_user_id, checker, polarity))
  end

  # A none or an all asking about the actor of an anonymous session asks about nobody as a whole,
  # which grants nothing - its condition alone would come out false and turn it true.
  defp clause_holds?({quantifier, {source, clauses}}, rows, nil, checker, polarity)
       when quantifier in [:all, :none] do
    if Stage.names_actor?(clauses) do
      false
    else
      quantifier_holds?({quantifier, source, clauses}, rows, nil, checker, polarity)
    end
  end

  defp clause_holds?({quantifier, {source, clauses}}, rows, actor_user_id, checker, polarity)
       when quantifier in @quantifiers do
    quantifier_holds?({quantifier, source, clauses}, rows, actor_user_id, checker, polarity)
  end

  defp clause_holds?(triple, rows, actor_user_id, checker, _polarity) do
    predicate_holds?(triple, rows, actor_user_id, checker)
  end

  defp compare(%Date{} = left, %Date{} = right), do: Date.compare(left, right)

  defp compare(%DateTime{} = left, %DateTime{} = right), do: DateTime.compare(left, right)

  defp compare(%Time{} = left, %Time{} = right), do: Time.compare(left, right)

  # A policy compares a string the way a query does - by the key derived from it, then by the
  # value behind it - so a rule and the filter mirroring it admit the same rows. The key is a
  # bounded prefix, which is what leaves the value something to settle.
  defp compare(left, right) when is_binary(left) and is_binary(right) do
    case plain_compare(SortKey.compute(left), SortKey.compute(right)) do
      :eq -> plain_compare(left, right)
      result -> result
    end
  end

  defp compare(left, right) when left < right, do: :lt

  defp compare(left, right) when left > right, do: :gt

  defp compare(_left, _right), do: :eq

  defp plain_compare(left, right) when left < right, do: :lt

  defp plain_compare(left, right) when left > right, do: :gt

  defp plain_compare(_left, _right), do: :eq

  # An enum value compares by its position in the list the entity declares, which is the order
  # the database holds the type in and the order a query compares it by - so a rule and the
  # filter mirroring it admit the same rows. A value the list does not hold is a bug surfacing
  # rather than a case to place.
  defp compare(left, right, nil), do: compare(left, right)

  defp compare(left, right, ranks) do
    compare(Map.fetch!(ranks, left), Map.fetch!(ranks, right))
  end

  # What an enum predicate compares by, or nil for an attribute of any other type - a name
  # matching no attribute definition is a reference field, which carries an entity id. A path's
  # ranks are those of the attribute it ends at, and a name of a row above those of that row's type.
  defp enum_ranks(rows, {:outer, levels, name}), do: enum_ranks(Enum.drop(rows, levels), name)

  defp enum_ranks([%entity_type{} | _outer_rows], name), do: enum_ranks(entity_type, name)

  defp enum_ranks(entity_type, [_hop | _later_names] = path) do
    {relationship_names, [name]} = Enum.split(path, -1)

    entity_type
    |> Entity.path_target(relationship_names)
    |> enum_ranks(name)
  end

  defp enum_ranks(entity_type, name) do
    definitions = entity_type.__attributes__() ++ entity_type.__derived__()

    case List.keyfind(definitions, name, 0) do
      {_name, :enum, opts} ->
        opts
        |> Keyword.fetch!(:values)
        |> Enum.with_index()
        |> Map.new()

      _other ->
        nil
    end
  end

  defp equal?(left, right), do: compare(left, right) == :eq

  # A derived field's definition on the row - strings joined, nil when one of them is, an if's
  # branch, whether a condition holds, a name read the way a rule reads it, or a value.
  defp evaluated({:concat, operands}, rows, actor_user_id, checker) do
    values = Enum.map(operands, &evaluated(&1, rows, actor_user_id, checker))

    if Enum.any?(values, &is_nil/1), do: nil, else: Enum.join(values)
  end

  defp evaluated({:condition, clauses}, rows, actor_user_id, checker) do
    predicates_hold?(clauses, rows, actor_user_id, checker, :positive)
  end

  defp evaluated({:if, clauses, then_value, else_value}, rows, actor_user_id, checker) do
    if predicates_hold?(clauses, rows, actor_user_id, checker, :positive) do
      evaluated(then_value, rows, actor_user_id, checker)
    else
      evaluated(else_value, rows, actor_user_id, checker)
    end
  end

  defp evaluated({:name, name}, rows, actor_user_id, checker) do
    read_value(rows, name, actor_user_id, checker)
  end

  defp evaluated({:value, value}, _rows, _actor_user_id, _checker), do: value

  defp holds?(field_value, :==, value, _ranks), do: equal?(field_value, value)

  defp holds?(field_value, :!=, value, _ranks), do: not equal?(field_value, value)

  defp holds?(field_value, :in, values, _ranks) do
    Enum.any?(values, &equal?(field_value, &1))
  end

  defp holds?(field_value, :not_in, values, _ranks) do
    not Enum.any?(values, &equal?(field_value, &1))
  end

  defp holds?(nil, operator, _value, _ranks) when operator in @ordering_operators, do: false

  defp holds?(_field_value, operator, nil, _ranks) when operator in @ordering_operators do
    false
  end

  # A search never matches a missing value either, and a rule and the filter mirroring it have to
  # admit the same rows - so it matches the way a query does, by bytes or by folded forms.
  defp holds?(nil, operator, _value, _ranks) when operator in @search_operators, do: false

  defp holds?(_field_value, operator, nil, _ranks) when operator in @search_operators, do: false

  defp holds?(field_value, :contains, value, _ranks) do
    field_value
    |> SortKey.fold()
    |> String.contains?(SortKey.fold(value))
  end

  defp holds?(field_value, :contains_exact, value, _ranks),
    do: String.contains?(field_value, value)

  defp holds?(field_value, :starts_with, value, _ranks) do
    field_value
    |> SortKey.fold()
    |> String.starts_with?(SortKey.fold(value))
  end

  defp holds?(field_value, :starts_with_exact, value, _ranks),
    do: String.starts_with?(field_value, value)

  defp holds?(field_value, :<, value, ranks), do: compare(field_value, value, ranks) == :lt

  defp holds?(field_value, :<=, value, ranks), do: compare(field_value, value, ranks) != :gt

  defp holds?(field_value, :>, value, ranks), do: compare(field_value, value, ranks) == :gt

  defp holds?(field_value, :>=, value, ranks), do: compare(field_value, value, ranks) != :lt

  # Nobody is equal to no attribute and unequal to none - asking about the actor of an anonymous
  # session is asking about nobody, which no row answers.
  defp predicate_holds?({_name, _operator, {:actor}}, _rows, nil, _checker), do: false

  # Another attribute of the row, compared the way a literal is - by the predicate's attribute's
  # ranks, since two enums compare only when they declare the same list.
  defp predicate_holds?({name, operator, {:attribute, other}}, rows, actor_user_id, checker) do
    ranks = enum_ranks(rows, name)
    other_value = read_value(rows, other, actor_user_id, checker)

    rows
    |> read_value(name, actor_user_id, checker)
    |> holds?(operator, other_value, ranks)
  end

  defp predicate_holds?({name, operator, value}, rows, actor_user_id, checker) do
    ranks = enum_ranks(rows, name)

    rows
    |> read_value(name, actor_user_id, checker)
    |> holds?(operator, resolve_value(value, actor_user_id), ranks)
  end

  defp predicates_hold?(clauses, rows, actor_user_id, checker, polarity) do
    Enum.all?(clauses, &clause_holds?(&1, rows, actor_user_id, checker, polarity))
  end

  # Whether the condition holds for any, none or every row of the set the source leads to, read on
  # the row the quantifier is about or on the row above it the source names. Each related row is
  # matched with the rows above it, so its condition reads them by how many quantifiers out they are.
  #
  # The set is asked for whole - {:set, relationship names, :whole} - when a row joining it could
  # turn the rule's grant into a refusal, which a write resting on the answer has to keep out.
  defp quantifier_holds?({quantifier, source, clauses}, rows, actor_user_id, checker, polarity) do
    {[source_row | _outer_rows], relationship_names} = source_rows(rows, source)
    condition_polarity = Stage.condition_polarity(quantifier, polarity)

    matches? = fn related_row ->
      predicates_hold?(clauses, [related_row | rows], actor_user_id, checker, condition_polarity)
    end

    requirement =
      if Stage.joining_row_refuses?(quantifier, polarity),
        do: {:set, relationship_names, :whole},
        else: {:set, relationship_names}

    related_rows = checker.(requirement, source_row, actor_user_id)

    case quantifier do
      :all -> Enum.all?(related_rows, matches?)
      :any -> Enum.any?(related_rows, matches?)
      :none -> not Enum.any?(related_rows, matches?)
    end
  end

  # A name of a row above is read on that row.
  defp read_value(rows, {:outer, levels, name}, actor_user_id, checker) do
    rows
    |> Enum.drop(levels)
    |> read_value(name, actor_user_id, checker)
  end

  # A path's value is its last name read off the row the relationships before it lead to, and nil
  # when they lead nowhere.
  defp read_value([row | _outer_rows], [_hop | _later_names] = path, actor_user_id, checker) do
    {relationship_names, [name]} = Enum.split(path, -1)

    case checker.({:related, relationship_names}, row, actor_user_id) do
      nil -> nil
      related_row -> read_value([related_row], name, actor_user_id, checker)
    end
  end

  # A derived field is computed from its definition, resolved natively - one a condition reads calls
  # no query builder - on the row it is read on alone. An integer a float field reads compares equal
  # to its float, so it stays as is.
  defp read_value([%entity_type{} = row | _outer_rows], name, actor_user_id, checker) do
    case List.keyfind(entity_type.__derived__(), name, 0) do
      {_name, _type, _opts} ->
        entity_type
        |> Derived.resolve(name)
        |> evaluated([row], actor_user_id, checker)

      nil ->
        Map.fetch!(row, name)
    end
  end

  defp resolve_value({:actor}, actor_user_id), do: actor_user_id

  defp resolve_value(value, _actor_user_id), do: value

  # The rows a source is read on: the row the quantifier is about and the rows above it, or - for a
  # source read on a row above - that row and the rows above it.
  defp source_rows(rows, {:outer, levels, relationship_names}),
    do: {Enum.drop(rows, levels), relationship_names}

  defp source_rows(rows, relationship_names), do: {rows, relationship_names}

  defp to_holds?(nil, _entity, _actor_user_id, _checker), do: true

  # A role is held by somebody, so an anonymous session holds none - the grant store is not asked.
  defp to_holds?(_references, _entity, nil, _checker), do: false

  defp to_holds?(references, entity, actor_user_id, checker) do
    Enum.any?(references, &checker.(&1, entity, actor_user_id))
  end

  defp via_holds?(nil, _entity, _actor_user_id, _checker), do: true

  defp via_holds?({operation, relationship_names}, entity, actor_user_id, checker) do
    checker.({:via, operation, relationship_names}, entity, actor_user_id)
  end
end
