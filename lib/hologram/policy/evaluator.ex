defmodule Hologram.Policy.Evaluator do
  @moduledoc false

  # In-memory evaluation of compiled policy rules against entity structs. Predicates are
  # evaluated here, while grant references and delegations are resolved by the checker
  # function the caller injects - they need the grant store and the related rows, which
  # this module deliberately knows nothing about.

  alias Hologram.DB.SortKey
  alias Hologram.Entity
  alias Hologram.Entity.Derived

  @ordering_operators [:<, :<=, :>, :>=]

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

  For an anonymous session a user_id() predicate is false, whichever way it points, and a grant
  reference is held by nobody - the actor is nobody rather than nil, since a nil actor would make
  rows with a missing reference match everyone. So a conjunction naming the actor fails, and a
  disjunction answers through its other alternatives: `author_id == user_id() or shared == true`
  still grants a visitor the shared rows. A delegating rule is evaluated as any other, because the
  entity type it delegates to answers its own actor-referencing rules the same way.

  Grant references, delegations and the rows a path reads are resolved by the given checker
  function, called as checker.(requirement, entity, actor user id). For the rule's grant reference
  or a {:via, operation, chain} tuple - the chain of to-one relationships followed to the related
  row - it returns a boolean. For a {:related, relationship names} tuple it returns the row those
  relationships lead to, or nil when one of them is empty or names a row that is gone.
  """
  @spec rule_matches?(map, struct, String.t() | nil, fun) :: boolean
  def rule_matches?(rule, entity, actor_user_id, checker) do
    predicates_hold?(rule.predicates, entity, actor_user_id, checker) and
      to_holds?(rule.to, entity, actor_user_id, checker) and
      via_holds?(rule.via, entity, actor_user_id, checker)
  end

  defp clause_holds?({:or, alternatives}, entity, actor_user_id, checker) do
    Enum.any?(alternatives, &predicates_hold?(&1, entity, actor_user_id, checker))
  end

  defp clause_holds?(triple, entity, actor_user_id, checker) do
    predicate_holds?(triple, entity, actor_user_id, checker)
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
  # ranks are those of the attribute it ends at.
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
  defp evaluated({:concat, operands}, entity, actor_user_id, checker) do
    values = Enum.map(operands, &evaluated(&1, entity, actor_user_id, checker))

    if Enum.any?(values, &is_nil/1), do: nil, else: Enum.join(values)
  end

  defp evaluated({:condition, clauses}, entity, actor_user_id, checker) do
    predicates_hold?(clauses, entity, actor_user_id, checker)
  end

  defp evaluated({:if, clauses, then_value, else_value}, entity, actor_user_id, checker) do
    if predicates_hold?(clauses, entity, actor_user_id, checker) do
      evaluated(then_value, entity, actor_user_id, checker)
    else
      evaluated(else_value, entity, actor_user_id, checker)
    end
  end

  defp evaluated({:name, name}, entity, actor_user_id, checker) do
    read_value(entity, name, actor_user_id, checker)
  end

  defp evaluated({:value, value}, _entity, _actor_user_id, _checker), do: value

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
  defp predicate_holds?({_name, _operator, {:actor}}, _entity, nil, _checker), do: false

  # Another attribute of the row, compared the way a literal is - by the predicate's attribute's
  # ranks, since two enums compare only when they declare the same list.
  defp predicate_holds?({name, operator, {:attribute, other}}, entity, actor_user_id, checker) do
    ranks = enum_ranks(entity.__struct__, name)
    other_value = read_value(entity, other, actor_user_id, checker)

    entity
    |> read_value(name, actor_user_id, checker)
    |> holds?(operator, other_value, ranks)
  end

  defp predicate_holds?({name, operator, value}, entity, actor_user_id, checker) do
    ranks = enum_ranks(entity.__struct__, name)

    entity
    |> read_value(name, actor_user_id, checker)
    |> holds?(operator, resolve_value(value, actor_user_id), ranks)
  end

  defp predicates_hold?(clauses, entity, actor_user_id, checker) do
    Enum.all?(clauses, &clause_holds?(&1, entity, actor_user_id, checker))
  end

  # A path's value is its last name read off the row the relationships before it lead to, and nil
  # when they lead nowhere.
  defp read_value(entity, [_hop | _later_names] = path, actor_user_id, checker) do
    {relationship_names, [name]} = Enum.split(path, -1)

    case checker.({:related, relationship_names}, entity, actor_user_id) do
      nil -> nil
      row -> read_value(row, name, actor_user_id, checker)
    end
  end

  # A derived field is computed from its definition, resolved natively - one a condition reads calls
  # no query builder. An integer a float field reads compares equal to its float, so it stays as is.
  defp read_value(%entity_type{} = entity, name, actor_user_id, checker) do
    case List.keyfind(entity_type.__derived__(), name, 0) do
      {_name, _type, _opts} ->
        entity_type
        |> Derived.resolve(name)
        |> evaluated(entity, actor_user_id, checker)

      nil ->
        Map.fetch!(entity, name)
    end
  end

  defp resolve_value({:actor}, actor_user_id), do: actor_user_id

  defp resolve_value(value, _actor_user_id), do: value

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
