defmodule Hologram.Policy.Edges do
  @moduledoc false

  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.Query.Stage

  @index_key {__MODULE__, :index}

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
      row reached by following the chain: what a path in a condition reads, a reference field a
      longer path is followed through, or what a delegated predicate reads.
    * `{:set_attributes, chain, entity_type, names}` - attributes of the rows of the set the
      chain reaches through a to-many or an inverse relationship: what a quantifier's condition
      reads on them, a reference field followed further from them, or the reference field an
      inverse of a to-one reads its rows by, which a row joining or leaving the set changes.
    * `{:set_edges, chain, entity_type, relationship_names}` - pairs of these to-many
      relationships stored on the entity type, which put rows into the set the chain reaches -
      the owner's to-many, or the to-many an inverse of one reverses.
    * `{:named_grants, entity_type, role_names}` - grants of these roles held on the
      entity a grant-store row names, deciding that row's visibility.

  Delegations expand transitively: a via chain contributes the target policy's edges for the
  operation each delegation names, with the chain prefixed, so every pair's list is complete on
  its own. Edges may over-approximate the affected data - re-checking everything an edge names
  is slower than necessary, never wrong - and they never under-approximate.

  Takes a validated data model: the transitive expansion follows delegation to its end, so a
  via cycle would not terminate. Cycles are a compile error, raised by
  `Hologram.Policy.Validator.validate_model!/2` before anything reads the model - the same
  guarantee SQL composition relies on to terminate. A model under a hold, whose loaded code no
  compile may have validated, raises rather than loops: the policies are built through
  `Hologram.Policy.build/1`, which refuses it (see `Hologram.Entity.Model.hold/0`).
  """
  @spec derive(list(module)) :: %{{module, Entity.operation()} => list(tuple)}
  def derive(entity_types) do
    for entity_type <- entity_types,
        {operation, rules} <- Policy.build(entity_type),
        into: %{} do
      {{entity_type, operation}, operation_edges(entity_type, rules)}
    end
  end

  @doc """
  Returns the dependency edges of every entity type in the project's compiled data model.

  Cached for the lifetime of the runtime and derived on the first call: deriving grows with the
  model, tens of milliseconds for hundreds of entity types. Resetting the cache drops it, so a
  recompiled data model is picked up by the next call. Raises while the data model is under a hold,
  cached or not (see `Hologram.Entity.Model.ensure_released!/0`).
  """
  @spec index() :: %{{module, Entity.operation()} => list(tuple)}
  def index do
    Model.ensure_released!()

    case :persistent_term.get(@index_key, nil) do
      nil ->
        index = derive(Model.entity_types())

        :persistent_term.put(@index_key, index)

        index

      index ->
        index
    end
  end

  @doc false
  @spec reset_index_cache() :: :ok
  def reset_index_cache do
    :persistent_term.erase(@index_key)

    :ok
  end

  @doc """
  Returns the invalidation kinds applying to every {entity type, operation} pair: an auth
  change invalidates the session's visibility wholesale, and a deploy re-evaluates
  everything under the new build's policies.
  """
  @spec universal_edges() :: list(atom)
  def universal_edges, do: @universal_edges

  # The reference fields a chain of to-one relationships is followed through: the first on the row
  # itself, every later one on the row the relationships before it lead to - so a related row
  # moving to another one is a change the edges name.
  defp chain_edges(entity_type, [first_relationship_name | _later_names] = relationship_names) do
    later_edges =
      relationship_names
      |> Enum.with_index()
      |> Enum.drop(1)
      |> Enum.map(fn {relationship_name, index} ->
        chain = Enum.take(relationship_names, index)

        {:relationship_attributes, chain, Entity.path_target(entity_type, chain),
         [reference_field_name(relationship_name)]}
      end)

    [{:attributes, [reference_field_name(first_relationship_name)]} | later_edges]
  end

  # A delegated edge names the same data as many relationship hops further away as the delegation
  # follows: the target's own-row dependencies become related-row dependencies through the chain,
  # its own grants become related-row grants, and edges naming absolute targets (global,
  # type-wide, named) pass through unchanged - a global grant event affects the delegating type
  # exactly as it affects the target.
  defp lift_edge({:attributes, names}, relationship_names, target_type) do
    {:relationship_attributes, relationship_names, target_type, names}
  end

  defp lift_edge({:own_grants, role_names}, relationship_names, target_type) do
    {:relationship_grants, relationship_names, target_type, role_names}
  end

  defp lift_edge(
         {:relationship_attributes, chain, chain_target, names},
         relationship_names,
         _target
       ) do
    {:relationship_attributes, relationship_names ++ chain, chain_target, names}
  end

  defp lift_edge(
         {:relationship_grants, chain, chain_target, role_names},
         relationship_names,
         _target
       ) do
    {:relationship_grants, relationship_names ++ chain, chain_target, role_names}
  end

  defp lift_edge({kind, chain, chain_target, names}, relationship_names, _target)
       when kind in [:set_attributes, :set_edges] do
    {kind, relationship_names ++ chain, chain_target, names}
  end

  defp lift_edge(edge, _relationship_names, _target_type), do: edge

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

  defp operation_edges(entity_type, rules) do
    rules
    |> Enum.flat_map(&rule_edges(entity_type, &1))
    |> merge_edges()
  end

  # A disjunction reads the row's own attributes like any other condition, and so does a comparison
  # between two of them, so neither adds an edge kind - their attributes join the rule's. A path
  # reads the attribute of the row its relationships lead to, and the reference fields it is
  # followed through. A derived field reads what its definition reads, written in place. A
  # quantifier reads the attributes its condition names on the rows of its set, and the rows its
  # source follows to get there, whether or not its condition reads any.
  defp predicate_edges(entity_type, predicates) do
    references = Stage.predicate_references(predicates)

    {own_references, path_references} =
      entity_type
      |> Derived.expanded_references(references)
      |> Enum.split_with(fn {relationship_names, _name} -> relationship_names == [] end)

    own_edges =
      case Enum.map(own_references, fn {_relationship_names, name} -> name end) do
        [] -> []
        names -> [{:attributes, names}]
      end

    path_edges =
      Enum.flat_map(path_references, fn {relationship_names, name} ->
        target_type = Entity.path_target(entity_type, relationship_names)
        {walked_edges, through_set?} = walked_edges(entity_type, relationship_names)
        kind = if through_set?, do: :set_attributes, else: :relationship_attributes

        [{kind, relationship_names, target_type, [name]} | walked_edges]
      end)

    source_edges =
      predicates
      |> Stage.relationship_chains()
      |> Enum.flat_map(fn chain ->
        {walked_edges, _through_set?} = walked_edges(entity_type, chain)

        walked_edges
      end)

    own_edges ++ path_edges ++ source_edges
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

  # A role held on the row a chain of relationships leads to reads the reference fields the chain is
  # followed through, and the grants held on that row.
  defp reference_edges_for(entity_type, {:rel, relationship_names, role_names}) do
    target_type = Entity.path_target(entity_type, relationship_names)

    [
      {:relationship_grants, relationship_names, target_type, role_names}
      | chain_edges(entity_type, relationship_names)
    ]
  end

  defp reference_edges_for(_entity_type, {:named, target_type, role_names}) do
    [{:named_grants, target_type, role_names}]
  end

  # The `<name>_id` atoms exist wherever entity structs do - they are the structs' reference
  # fields.
  defp reference_field_name(relationship_name) do
    String.to_existing_atom("#{relationship_name}_id")
  end

  defp rule_edges(entity_type, %{predicates: predicates, to: to, via: via}) do
    predicate_edges(entity_type, predicates) ++
      reference_edges(entity_type, to) ++
      via_edges(entity_type, via)
  end

  defp via_edges(_entity_type, nil), do: []

  # The target's edges are those of the operation the delegation asks it, which need not be the
  # delegating rule's own, lifted through the chain the delegation follows - beside the reference
  # fields it is followed through.
  defp via_edges(entity_type, {delegated_operation, relationship_names}) do
    target_type = Entity.path_target(entity_type, relationship_names)

    target_rules =
      target_type
      |> Policy.build()
      |> Map.get(delegated_operation, [])

    lifted_edges =
      target_type
      |> operation_edges(target_rules)
      |> Enum.map(&lift_edge(&1, relationship_names, target_type))

    chain_edges(entity_type, relationship_names) ++ lifted_edges
  end

  defp walked_edge(type, name, chain, link_chain, through_set?) do
    case Entity.inverse_relationship(type, name) do
      %{reference?: true, forward: forward, target: target_type} ->
        {{:set_attributes, link_chain, target_type, [reference_field_name(forward)]}, true}

      %{forward: forward, target: target_type} ->
        {{:set_edges, link_chain, target_type, [forward]}, true}

      nil ->
        cond do
          is_list(Entity.relationship_target(type, name)) ->
            {{:set_edges, link_chain, type, [name]}, true}

          through_set? ->
            {{:set_attributes, chain, type, [reference_field_name(name)]}, false}

          chain == [] ->
            {{:attributes, [reference_field_name(name)]}, false}

          true ->
            {{:relationship_attributes, chain, type, [reference_field_name(name)]}, false}
        end
    end
  end

  # What following each relationship of a chain from the given type reads, and whether the chain
  # went through a set: a stored to-one its reference field, on the row itself for the first one and
  # on the row the relationships before it lead to after that - on the rows of a set once one is
  # behind - an inverse of a to-one the reference field its rows are read by, and a to-many or an
  # inverse of one the pairs that hold its rows.
  defp walked_edges(entity_type, relationship_names) do
    {edges, _type, through_set?} =
      relationship_names
      |> Enum.with_index()
      |> Enum.reduce({[], entity_type, false}, fn {name, index}, {acc, type, through_set?} ->
        chain = Enum.take(relationship_names, index)
        link_chain = Enum.take(relationship_names, index + 1)

        {edge, set_link?} = walked_edge(type, name, chain, link_chain, through_set?)

        {[edge | acc], Entity.related_type(type, name), through_set? or set_link?}
      end)

    {Enum.reverse(edges), through_set?}
  end
end
