defmodule Hologram.Policy.Readers do
  @moduledoc false

  alias Hologram.Entity
  alias Hologram.Policy
  alias Hologram.Query.Stage

  @typedoc """
  What bounds the users a rule holds for, or a deciding item answers differently for - each a
  superset of them:

    * `{:actor_equal, name}` - the value of the name, compared equal to the acting user.
    * `{:any, source, anchor}` - the anchor's users over every row of the set the source reaches.
    * `{:or, anchors}` - the users of any alternative.
    * `{:grants, references}` - the holders of any of the rule's grant references.
    * `{:via, operation, chain, rule_anchors}` - the users of the delegated rules' anchors, read on
      the row the chain leads to.
  """
  @type anchor ::
          {:actor_equal, atom | list(atom) | tuple}
          | {:any, list(atom) | tuple, anchor}
          | {:or, list(anchor)}
          | {:grants, list(tuple)}
          | {:via, Entity.operation(), list(atom), list({map, anchor})}

  @type class :: {:independent, map} | {:listed, map, anchor} | {:unlisted, map}

  @typedoc """
  How the users a deciding item answers differently for can be found from a row (see
  `classify_verdicts/1`).
  """
  @type verdict_class :: :independent | {:listed, anchor, boolean} | :unlisted

  @doc """
  Returns the rules granting the given operation on the given entity type, split and classified by
  how the users they hold for can be found from a row. A field of an update is granted by the
  limited lines covering it and the ones covering the whole row (see
  `Hologram.Policy.operation_rules/2`).

  Rules are split first, without changing what the policy grants:

    * a disjunction among a rule's top-level clauses becomes one rule per alternative - one per
      combination when there are several, a disjunction inside an alternative distributed too - so
      an alternative naming nobody is decided apart from the ones naming the acting user.
      Disjunctions inside a quantifier stay.
    * a delegation becomes one rule per class of the delegated rules, its via carrying those rules
      as `{operation, chain, rules}`. A rule holds when its own conditions and one delegated rule
      do, so it holds exactly when one of the split rules does. A delegation to an operation the
      related type declares no rule for never holds, so its rule is dropped.

  Each split rule is then one of:

    * `{:independent, rule}` - it names neither the acting user nor a role, and delegates only to
      independent rules, so it answers the same for every user, anonymous ones included.
    * `{:listed, rule, anchor}` - a condition it requires bounds the users it can hold for (see
      `t:anchor/0`): the first one found, in its predicates, then its grant references, then its
      delegation.
    * `{:unlisted, rule}` - nothing bounds them, like `owner_id != user_id()`, or the acting user
      named only inside a `none` or an `all`, which can hold with no row matching.

  Takes a validated data model: delegations are followed to their end, which a via cycle would
  not reach.
  """
  @spec classify(module, Entity.operation()) :: list(class)
  def classify(entity_type, operation \\ :read) do
    entity_type
    |> Policy.build()
    |> Policy.operation_rules(operation)
    |> Enum.flat_map(&split_disjunctions/1)
    |> Enum.flat_map(&split_delegation(&1, entity_type))
    |> Enum.map(&classify_rule/1)
  end

  @doc """
  Returns the deciding items of the given entity type
  (see `Hologram.Policy.deciding_quantifiers/1`), each once with every verdict key it answers, in
  the order of their first keys, and classified by how the users it answers differently for can be
  found from a row:

    * `:independent` - it names no acting user, so it answers the same for every user, anonymous
      ones included.
    * `{:listed, anchor, default}` - it answers the default for every signed-in user the anchor
      can't name (see `t:anchor/0`): false for an equality on the acting user, for an `any`
      bounded by a condition it requires, for a role reference, whose holders a `:grants` anchor
      names, and for a delegation whose rules asked of the related row are all listed, whose
      users a `:via` anchor names, and true for a `none` whose condition is bounded so, since it
      holds exactly when that `any` doesn't, and for an `all` whose condition is one `!=` on the
      acting user, the `none` of the equality.
    * `:unlisted` - nothing bounds them, like a `!=` on the acting user or any other `all`.

  A clause carries no grant reference and no delegation - those are a rule's own - so nothing
  but its conditions decide it, a role reference is decided by the grants alone, and a delegation
  by the rules it asks of the related row. An anonymous user is no user an anchor names, but a
  `none` or an `all` naming the acting user answers no for one (see `Hologram.Policy.Evaluator`),
  and so does a role reference, so a default is only ever a signed-in user's answer.
  """
  @spec classify_verdicts(module) :: list({tuple, list(String.t()), verdict_class})
  def classify_verdicts(entity_type) do
    pairs = Policy.deciding_quantifiers(entity_type)

    pairs
    |> Enum.map(fn {_key, item} -> item end)
    |> Enum.uniq()
    |> Enum.map(fn item ->
      keys = for {key, ^item} <- pairs, do: key

      {item, keys, verdict_class(entity_type, item)}
    end)
  end

  # An any holds when one row of its set matches, so the users its condition is bounded by on that
  # row bound it. A none or an all can hold with no row matching, so it bounds nothing it holds for
  # - the users a none, or an all of one inequality, fails for are another matter (see
  # none_anchor/1).
  defp clause_anchor({name, :==, {:actor}}), do: {:actor_equal, name}

  defp clause_anchor({:any, {source, clauses}}) do
    case predicates_anchor(clauses) do
      nil -> nil
      anchor -> {:any, source, anchor}
    end
  end

  defp clause_anchor({:or, alternatives}) do
    anchors = Enum.map(alternatives, &predicates_anchor/1)

    if Enum.all?(anchors), do: {:or, anchors}
  end

  defp clause_anchor(_clause), do: nil

  defp classify_rule({rule, via_class}) do
    if via_class in [nil, :independent] and rule.to == nil and
         not Stage.names_actor?(rule.predicates) do
      {:independent, rule}
    else
      case rule_anchor(rule, via_class) do
        nil -> {:unlisted, rule}
        anchor -> {:listed, rule, anchor}
      end
    end
  end

  defp class_name({:independent, _rule}), do: :independent

  defp class_name({:listed, _rule, _anchor}), do: :listed

  defp class_name({:unlisted, _rule}), do: :unlisted

  defp class_rule({:listed, rule, _anchor}), do: rule

  defp class_rule({_class_name, rule}), do: rule

  # Every conjunction the given clauses hold once their disjunctions are distributed, the
  # disjunctions inside an alternative included. Each is built reversed, a clause pushed on its
  # head, and a clause it ends up holding twice is kept once.
  defp conjunctions(clauses) do
    clauses
    |> Enum.reduce([[]], fn
      {:or, alternatives}, reversed_conjunctions ->
        for conjunction <- reversed_conjunctions,
            alternative <- alternatives,
            alternative_conjunction <- conjunctions(alternative) do
          Enum.reverse(alternative_conjunction, conjunction)
        end

      clause, reversed_conjunctions ->
        Enum.map(reversed_conjunctions, &[clause | &1])
    end)
    |> Enum.map(fn reversed_conjunction ->
      reversed_conjunction
      |> Enum.reverse()
      |> Enum.uniq()
    end)
  end

  # A none holds exactly when the any over the same set and condition doesn't, so whatever bounds
  # the users that any holds for bounds the users the none fails for. An all whose condition is
  # one inequality on the acting user is the none of the equality - a row with no value passes the
  # inequality and doesn't match the equality, so it counts against neither.
  defp none_anchor({:none, set}), do: clause_anchor({:any, set})

  defp none_anchor({:all, {source, [{name, :!=, {:actor}}]}}),
    do: clause_anchor({:any, {source, [{name, :==, {:actor}}]}})

  defp none_anchor(_clause), do: nil

  defp predicates_anchor(clauses), do: Enum.find_value(clauses, &clause_anchor/1)

  defp rule_anchor(rule, via_class) do
    cond do
      anchor = predicates_anchor(rule.predicates) ->
        anchor

      rule.to != nil ->
        {:grants, rule.to}

      match?({:listed, _rule_anchors}, via_class) ->
        {delegated_operation, chain, _rules} = rule.via
        {:listed, rule_anchors} = via_class

        {:via, delegated_operation, chain, rule_anchors}

      true ->
        nil
    end
  end

  defp split_delegation(%{via: nil} = rule, _entity_type), do: [{rule, nil}]

  defp split_delegation(%{via: {delegated_operation, chain}} = rule, entity_type) do
    target_classes =
      entity_type
      |> Entity.path_target(chain)
      |> classify(delegated_operation)

    target_classes
    |> Enum.group_by(&class_name/1)
    |> Enum.sort_by(fn {name, _classes} -> name end)
    |> Enum.map(fn {name, group} ->
      via = {delegated_operation, chain, Enum.map(group, &class_rule/1)}

      {%{rule | via: via}, via_class(name, group)}
    end)
  end

  defp split_disjunctions(rule) do
    rule.predicates
    |> conjunctions()
    |> Enum.map(&%{rule | predicates: &1})
  end

  defp verdict_class(_entity_type, {:to, reference}), do: {:listed, {:grants, [reference]}, false}

  # A delegation answers as the rules it asks of the related row: the same for every user when each
  # of them does - none at all among them, so it never holds - and false for every user their
  # anchors leave out when each of them is listed.
  defp verdict_class(entity_type, {:via, {delegated_operation, chain}}) do
    classes =
      entity_type
      |> Entity.path_target(chain)
      |> classify(delegated_operation)

    cond do
      Enum.all?(classes, &match?({:independent, _rule}, &1)) ->
        :independent

      Enum.all?(classes, &match?({:listed, _rule, _anchor}, &1)) ->
        rule_anchors = Enum.map(classes, fn {:listed, rule, anchor} -> {rule, anchor} end)

        {:listed, {:via, delegated_operation, chain, rule_anchors}, false}

      true ->
        :unlisted
    end
  end

  defp verdict_class(_entity_type, clause) do
    cond do
      not Stage.names_actor?([clause]) -> :independent
      anchor = clause_anchor(clause) -> {:listed, anchor, false}
      anchor = none_anchor(clause) -> {:listed, anchor, true}
      true -> :unlisted
    end
  end

  defp via_class(:listed, group) do
    {:listed, Enum.map(group, fn {:listed, rule, anchor} -> {rule, anchor} end)}
  end

  defp via_class(name, _group), do: name
end
