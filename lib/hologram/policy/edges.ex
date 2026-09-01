defmodule Hologram.Policy.Edges do
  @moduledoc false

  alias Hologram.Entity
  alias Hologram.Policy

  @universal_edges [:auth_change, :deploy]

  @doc """
  Derives the policy-to-data dependency edges of the given entity type modules: a map from
  {entity type, operation} to the sorted list of structural edges naming the data whose
  changes can change the operation's answers for some row and user.

  Edge kinds:

    * `{:attributes, names}` - attributes of the row itself, predicate operands and the
      `<relationship>_id` columns relationship-shaped rules read through.
    * `{:own_grants, role_names}` - grants of these roles held on the entity type's own rows
      or on the whole type.
    * `{:global_grants, role_modules}` - grants of these global role modules, held app-wide.
    * `{:type_grants, entity_type, role_names}` - grants of these roles held on another
      entity type as a whole.
    * `{:relationship_grants, chain, entity_type, role_names}` - grants of these roles held
      on the related row (or its whole type) reached by following the chain of to-one
      relationships.
    * `{:relationship_attributes, chain, entity_type, names}` - attributes of the related
      row reached by following the chain, read by delegated predicates.
    * `{:resource_grants, entity_type, role_names}` - grants of these roles held on the
      resource a grant-store row names, deciding that row's visibility.

  Delegations expand transitively: a via chain contributes the target policy's edges with
  the chain prefixed, so every pair's list is complete on its own. Edges may over-approximate
  the affected data - re-checking everything an edge names is slower than necessary, never
  wrong - and they never under-approximate.

  Takes a validated data model: the transitive expansion follows delegation to its end, so a
  via cycle would not terminate. Cycles are a compile error, raised by
  `Hologram.Policy.Validator.validate_model!/1` before anything reads the model - the same
  guarantee SQL composition relies on to keep the table names of a chain distinct.
  """
  @spec derive(list(module)) :: %{{module, Entity.operation()} => list(tuple)}
  def derive(entity_types) do
    for entity_type <- entity_types,
        {operation, rules} <- Policy.build(entity_type),
        into: %{} do
      {{entity_type, operation}, operation_edges(entity_type, operation, rules)}
    end
  end

  @doc """
  Returns the invalidation kinds applying to every {entity type, operation} pair: an auth
  change invalidates the session's visibility wholesale, and a deploy re-evaluates
  everything under the new build's policies.
  """
  @spec universal_edges() :: list(atom)
  def universal_edges, do: @universal_edges

  # A delegated edge names the same data one relationship hop further away: the target's
  # own-row dependencies become related-row dependencies through the chain, its own grants
  # become related-row grants, and edges naming absolute targets (global, type-wide,
  # resource) pass through unchanged - a global grant event affects the delegating type
  # exactly as it affects the target.
  defp lift_edge({:attributes, names}, relationship_name, target_type) do
    {:relationship_attributes, [relationship_name], target_type, names}
  end

  defp lift_edge({:own_grants, role_names}, relationship_name, target_type) do
    {:relationship_grants, [relationship_name], target_type, role_names}
  end

  defp lift_edge(
         {:relationship_attributes, chain, chain_target, names},
         relationship_name,
         _target
       ) do
    {:relationship_attributes, [relationship_name | chain], chain_target, names}
  end

  defp lift_edge(
         {:relationship_grants, chain, chain_target, role_names},
         relationship_name,
         _target
       ) do
    {:relationship_grants, [relationship_name | chain], chain_target, role_names}
  end

  defp lift_edge(edge, _relationship_name, _target_type), do: edge

  # Edges sharing a kind, target, and chain merge by unioning their name lists, so each
  # pair's list states every dependency of one shape exactly once.
  defp merge_edges(edges) do
    edges
    |> Enum.group_by(&Tuple.delete_at(&1, tuple_size(&1) - 1))
    |> Enum.map(fn {discriminator, group} ->
      names =
        group
        |> Enum.flat_map(&elem(&1, tuple_size(&1) - 1))
        |> Enum.uniq()
        |> Enum.sort()

      Tuple.insert_at(discriminator, tuple_size(discriminator), names)
    end)
    |> Enum.sort()
  end

  defp operation_edges(entity_type, operation, rules) do
    rules
    |> Enum.flat_map(&rule_edges(entity_type, operation, &1))
    |> merge_edges()
  end

  defp predicate_edges(predicates) do
    case Enum.map(predicates, fn {name, _operator, _value} -> name end) do
      [] -> []
      names -> [{:attributes, names}]
    end
  end

  defp reference_edges(_entity_type, nil), do: []

  defp reference_edges(entity_type, references) do
    Enum.flat_map(references, &reference_edges_for(entity_type, &1))
  end

  defp reference_edges_for(_entity_type, {:global, role_modules}) do
    [{:global_grants, role_modules}]
  end

  defp reference_edges_for(_entity_type, {:own, role_names}) do
    [{:own_grants, role_names}]
  end

  defp reference_edges_for(_entity_type, {:type, target_type, role_names}) do
    [{:type_grants, target_type, role_names}]
  end

  defp reference_edges_for(entity_type, {:rel, relationship_name, role_names}) do
    target_type = Entity.relationship_target(entity_type, relationship_name)

    [
      {:attributes, [reference_field_name(relationship_name)]},
      {:relationship_grants, [relationship_name], target_type, role_names}
    ]
  end

  defp reference_edges_for(_entity_type, {:resource, target_type, role_names}) do
    [{:resource_grants, target_type, role_names}]
  end

  # The `<name>_id` atoms exist wherever entity structs do - they are the structs' reference
  # fields.
  defp reference_field_name(relationship_name) do
    String.to_existing_atom("#{relationship_name}_id")
  end

  defp rule_edges(entity_type, operation, %{predicates: predicates, to: to, via: via}) do
    predicate_edges(predicates) ++
      reference_edges(entity_type, to) ++
      via_edges(entity_type, operation, via)
  end

  defp via_edges(_entity_type, _operation, nil), do: []

  defp via_edges(entity_type, operation, via) do
    target_type = Entity.relationship_target(entity_type, via)

    target_rules =
      target_type
      |> Policy.build()
      |> Map.get(operation, [])

    lifted_edges =
      target_type
      |> operation_edges(operation, target_rules)
      |> Enum.map(&lift_edge(&1, via, target_type))

    [{:attributes, [reference_field_name(via)]} | lifted_edges]
  end
end
