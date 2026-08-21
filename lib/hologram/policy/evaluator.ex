defmodule Hologram.Policy.Evaluator do
  @moduledoc false

  # In-memory evaluation of compiled policy rules against entity structs. Predicates are
  # evaluated here, while grant references and delegations are resolved by the checker
  # function the caller injects - they need the grant store and the related rows, which
  # this module deliberately knows nothing about.

  alias Hologram.DB.SortKey

  @ordering_operators [:<, :<=, :>, :>=]

  @doc """
  Returns true when the given operation's compiled policy grants it for the given entity struct, or false otherwise.

  An operation with no rules grants nothing, which is what makes the default deny.
  """
  @spec grants?(%{atom => list(map)}, atom, struct, String.t() | nil, fun) :: boolean
  def grants?(policy, operation, entity, actor_user_id, checker) do
    policy
    |> Map.get(operation, [])
    |> Enum.any?(&rule_matches?(&1, entity, actor_user_id, checker))
  end

  @doc """
  Returns true when the given compiled rule grants its operation for the given entity struct, or false otherwise.

  Every predicate must hold, one grant reference must be held, and the delegation must grant
  the same operation on the related entity. Predicate values compare as they do in the database:
  nil is a regular value for equality and membership, while ordering comparisons never match it.

  A rule referencing the actor - through a user_id() predicate or any grant reference - is
  skipped for an anonymous session instead of being evaluated with a nil actor, which would
  make rows with a missing reference match everyone. A delegating rule is still evaluated,
  because the entity type it delegates to skips its own actor-referencing rules in turn.

  Grant references and delegations are resolved by the given checker function, called as
  checker.(requirement, entity, actor user id) with the rule's grant reference or a
  {:via, relationship name} tuple, and returning a boolean.
  """
  @spec rule_matches?(map, struct, String.t() | nil, fun) :: boolean
  def rule_matches?(rule, entity, actor_user_id, checker) do
    if is_nil(actor_user_id) and actor_gated?(rule) do
      false
    else
      predicates_hold?(rule.predicates, entity, actor_user_id) and
        to_holds?(rule.to, entity, actor_user_id, checker) and
        via_holds?(rule.via, entity, actor_user_id, checker)
    end
  end

  defp actor_gated?(rule) do
    rule.to != nil or
      Enum.any?(rule.predicates, fn {_name, _operator, value} -> value == {:actor} end)
  end

  defp compare(%Date{} = left, %Date{} = right), do: Date.compare(left, right)

  defp compare(%DateTime{} = left, %DateTime{} = right), do: DateTime.compare(left, right)

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
  # matching no attribute definition is a reference field, which carries an entity id.
  defp enum_ranks(entity_type, name) do
    case List.keyfind(entity_type.__attributes__(), name, 0) do
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

  defp holds?(field_value, :<, value, ranks), do: compare(field_value, value, ranks) == :lt

  defp holds?(field_value, :<=, value, ranks), do: compare(field_value, value, ranks) != :gt

  defp holds?(field_value, :>, value, ranks), do: compare(field_value, value, ranks) == :gt

  defp holds?(field_value, :>=, value, ranks), do: compare(field_value, value, ranks) != :lt

  defp predicate_holds?({name, operator, value}, entity, actor_user_id) do
    ranks = enum_ranks(entity.__struct__, name)

    entity
    |> Map.fetch!(name)
    |> holds?(operator, resolve_value(value, actor_user_id), ranks)
  end

  defp predicates_hold?(predicates, entity, actor_user_id) do
    Enum.all?(predicates, &predicate_holds?(&1, entity, actor_user_id))
  end

  defp resolve_value({:actor}, actor_user_id), do: actor_user_id

  defp resolve_value(value, _actor_user_id), do: value

  defp to_holds?(nil, _entity, _actor_user_id, _checker), do: true

  defp to_holds?(references, entity, actor_user_id, checker) do
    Enum.any?(references, &checker.(&1, entity, actor_user_id))
  end

  defp via_holds?(nil, _entity, _actor_user_id, _checker), do: true

  defp via_holds?(relationship_name, entity, actor_user_id, checker) do
    checker.({:via, relationship_name}, entity, actor_user_id)
  end
end
