defmodule Hologram.Policy do
  @moduledoc false

  alias Hologram.Query
  alias Hologram.Reflection

  @doc """
  Validates the policy declarations of the given entity type modules as a whole.

  Returns :ok, or raises Hologram.CompileError naming the first invalid declaration.
  Policy declarations are checked here rather than when they are declared, because they are validated against compiled reflection - neither the declaring module nor the entity types it references are compiled while its body is executing.
  """
  @spec validate_model!(list(module)) :: :ok
  def validate_model!(entity_types) do
    validate_user_entity!(entity_types)

    Enum.each(entity_types, fn entity_type ->
      Enum.each(entity_type.__policies__(), fn {action, to, via, predicates} ->
        validate_to!(entity_type, action, to)
        validate_via!(entity_type, action, via)
        validate_predicates!(entity_type, action, predicates)
      end)
    end)

    validate_via_cycles!(entity_types)
  end

  # Rotates the cycle to start at its alphabetically first entity type, so that the same
  # cycle is always reported with the same hop order regardless of where traversal entered it.
  defp canonicalize_via_cycle(cycle) do
    start_index =
      cycle
      |> Enum.with_index()
      |> Enum.min_by(fn {{entity_type, relationship_name}, _index} ->
        {inspect(entity_type), relationship_name}
      end)
      |> elem(1)

    {hops_before_start, hops_from_start} = Enum.split(cycle, start_index)
    hops_from_start ++ hops_before_start
  end

  defp declared_role_names(entity_type) do
    Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)
  end

  defp describe_via_cycle([{first_entity_type, _first_relationship_name} | _later_hops] = cycle) do
    hops =
      Enum.map_join(cycle, " -> ", fn {entity_type, relationship_name} ->
        "#{inspect(entity_type)} (via #{inspect(relationship_name)})"
      end)

    "  * #{hops} -> #{inspect(first_entity_type)}"
  end

  # Depth-first traversal over the delegation edges of one action. The path holds the hops
  # taken to reach the current entity type (most recent first) - reaching an entity type
  # already on the path closes a cycle. Fully explored entity types are marked visited and
  # never re-entered, so each cycle is reported once.
  # TODO: identity features are detected through declarations only - grant_role and can?
  # callsites are not scanned yet, which the compiler's whole-program call graph analysis covers.
  defp declares_identity_features?(entity_type) do
    entity_type.__roles__() != [] or
      Enum.any?(entity_type.__policies__(), fn {_action, to, _via, _predicates} -> to != nil end)
  end

  defp find_via_cycles(entity_type, path, edges, {cycles, visited}) do
    if MapSet.member?(visited, entity_type) do
      {cycles, visited}
    else
      {cycles, visited} =
        edges
        |> Map.get(entity_type, [])
        |> Enum.reduce({cycles, visited}, fn {relationship_name, target_type}, acc ->
          follow_via_edge({entity_type, relationship_name}, target_type, path, edges, acc)
        end)

      {cycles, MapSet.put(visited, entity_type)}
    end
  end

  # Closes a cycle when the target is already on the path, descends into the target otherwise.
  defp follow_via_edge(hop, target_type, path, edges, {cycles, visited}) do
    new_path = [hop | path]

    if Enum.any?(new_path, fn {entity_type, _relationship_name} -> entity_type == target_type end) do
      {hops_beyond_target, [target_hop | _earlier_hops]} =
        Enum.split_while(new_path, fn {entity_type, _relationship_name} ->
          entity_type != target_type
        end)

      cycle = [target_hop | Enum.reverse(hops_beyond_target)]

      {[cycle | cycles], visited}
    else
      find_via_cycles(target_type, new_path, edges, {cycles, visited})
    end
  end

  defp relationship_target(entity_type, relationship_name) do
    {_name, target_type, _opts} =
      Enum.find(entity_type.__relationships__(), fn {name, _type, _opts} ->
        name == relationship_name
      end)

    target_type
  end

  defp to_reference_valid?(value) when is_atom(value), do: true

  defp to_reference_valid?({reference, role_name}) when is_atom(reference) and is_atom(role_name),
    do: true

  defp to_reference_valid?(_value), do: false

  defp to_value_valid?([_first_reference | _later_references] = value),
    do: Enum.all?(value, &to_reference_valid?/1)

  defp to_value_valid?(value), do: to_reference_valid?(value)

  defp validate_predicates!(entity_type, action, predicates) do
    Query.predicate_triples!(entity_type, predicates)

    :ok
  rescue
    error in ArgumentError ->
      message =
        "invalid predicate for allow #{inspect(action)} in #{inspect(entity_type)} - #{Exception.message(error)}"

      reraise Hologram.CompileError, [message: message], __STACKTRACE__
  end

  defp validate_relationship_reference!(entity_type, action, relationship_name, role_name) do
    definitions = entity_type.__relationships__()

    case Enum.find(definitions, fn {name, _type, _opts} -> name == relationship_name end) do
      {_name, [_target], _opts} ->
        raise Hologram.CompileError,
          message:
            "invalid to option #{inspect({relationship_name, role_name})} for allow #{inspect(action)} in #{inspect(entity_type)} - relationship #{inspect(relationship_name)} is to-many, but a role reference requires a to-one relationship"

      {_name, target, _opts} ->
        validate_target_role!(entity_type, action, target, role_name)

      nil ->
        declared_relationships =
          Enum.map_join(definitions, ", ", fn {name, _type, _opts} -> inspect(name) end)

        raise Hologram.CompileError,
          message:
            "unknown relationship #{inspect(relationship_name)} in the to option of allow #{inspect(action)} in #{inspect(entity_type)} - declared relationships are: #{declared_relationships}"
    end
  end

  defp validate_target_role!(entity_type, action, target_type, role_name) do
    declared_names = declared_role_names(target_type)

    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in the to option of allow #{inspect(action)} in #{inspect(entity_type)} - declared roles of #{inspect(target_type)} are: #{declared_roles}"
    end
  end

  defp validate_to!(_entity_type, _action, nil), do: :ok

  defp validate_to!(entity_type, action, to) do
    if not to_value_valid?(to) do
      raise Hologram.CompileError,
        message:
          "invalid to option #{inspect(to)} for allow #{inspect(action)} in #{inspect(entity_type)} - the to option must be a role name, a {module, role} or {relationship, role} tuple, or a non-empty list of them"
    end

    to
    |> List.wrap()
    |> Enum.each(&validate_to_reference!(entity_type, action, &1))
  end

  defp validate_to_reference!(entity_type, action, {reference, role_name}) do
    if Reflection.alias?(reference) do
      validate_type_reference!(entity_type, action, reference, role_name)
    else
      validate_relationship_reference!(entity_type, action, reference, role_name)
    end
  end

  defp validate_to_reference!(entity_type, action, role_name) do
    declared_names = declared_role_names(entity_type)

    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in the to option of allow #{inspect(action)} in #{inspect(entity_type)} - declared roles are: #{declared_roles}"
    end
  end

  defp validate_type_reference!(entity_type, action, target_type, role_name) do
    if not Reflection.entity?(target_type) do
      raise Hologram.CompileError,
        message:
          "invalid to option #{inspect({target_type, role_name})} for allow #{inspect(action)} in #{inspect(entity_type)} - #{inspect(target_type)} is not an entity type module"
    end

    validate_target_role!(entity_type, action, target_type, role_name)
  end

  defp validate_user_entity!(entity_types) do
    designated =
      entity_types
      |> Enum.filter(&Reflection.user_entity?/1)
      |> Enum.sort_by(&inspect/1)

    cond do
      length(designated) > 1 ->
        modules = Enum.map_join(designated, ", ", &inspect/1)

        raise Hologram.CompileError,
          message:
            "multiple user entity designations in the data model: #{modules} - exactly one entity type can be designated with use Hologram.Entity, user: true"

      designated == [] ->
        validate_user_entity_requirement!(entity_types)

      true ->
        :ok
    end
  end

  defp validate_user_entity_requirement!(entity_types) do
    entity_type =
      entity_types
      |> Enum.sort_by(&inspect/1)
      |> Enum.find(&declares_identity_features?/1)

    if entity_type do
      raise Hologram.CompileError,
        message:
          "#{inspect(entity_type)} declares roles or policy grant references, but no entity type is designated as the user entity - add use Hologram.Entity, user: true to your user module"
    end
  end

  defp validate_via!(_entity_type, _action, nil), do: :ok

  defp validate_via!(entity_type, action, via) do
    if not is_atom(via) do
      raise Hologram.CompileError,
        message:
          "invalid via option #{inspect(via)} for allow #{inspect(action)} in #{inspect(entity_type)} - the via option must be a relationship name"
    end

    definitions = entity_type.__relationships__()

    case Enum.find(definitions, fn {name, _type, _opts} -> name == via end) do
      {_name, [_target], _opts} ->
        raise Hologram.CompileError,
          message:
            "invalid via option #{inspect(via)} for allow #{inspect(action)} in #{inspect(entity_type)} - relationship #{inspect(via)} is to-many, but delegation requires a to-one relationship"

      {_name, _target, _opts} ->
        :ok

      nil ->
        declared_relationships =
          Enum.map_join(definitions, ", ", fn {name, _type, _opts} -> inspect(name) end)

        raise Hologram.CompileError,
          message:
            "unknown relationship #{inspect(via)} in the via option of allow #{inspect(action)} in #{inspect(entity_type)} - declared relationships are: #{declared_relationships}"
    end
  end

  defp validate_via_cycles!(entity_types) do
    entity_types
    |> via_edges()
    |> Enum.each(fn {action, action_edges} -> validate_via_cycles!(action, action_edges) end)
  end

  defp validate_via_cycles!(action, action_edges) do
    {cycles, _visited} =
      action_edges
      |> Map.keys()
      |> Enum.reduce({[], MapSet.new()}, fn entity_type, acc ->
        find_via_cycles(entity_type, [], action_edges, acc)
      end)

    if cycles != [] do
      descriptions =
        cycles
        |> Enum.map(&canonicalize_via_cycle/1)
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map_join("\n", &describe_via_cycle/1)

      raise Hologram.CompileError,
        message:
          "cyclic policy delegation for allow #{inspect(action)} - a via chain can't return to the entity type it starts from:\n#{descriptions}"
    end
  end

  defp via_declarations(entity_type) do
    entity_type.__policies__()
    |> Enum.reject(fn {_action, _to, via, _predicates} -> is_nil(via) end)
    |> Enum.map(fn {action, _to, via, _predicates} ->
      {action, entity_type, {via, relationship_target(entity_type, via)}}
    end)
  end

  # Delegation edges grouped as %{action => %{entity type => [{relationship name, target type}]}} -
  # a via chain delegates the SAME action, so each action forms its own independent graph.
  defp via_edges(entity_types) do
    entity_types
    |> Enum.flat_map(&via_declarations/1)
    |> Enum.group_by(
      fn {action, _entity_type, _edge} -> action end,
      fn {_action, entity_type, edge} -> {entity_type, edge} end
    )
    |> Map.new(fn {action, declarations} ->
      {action, Enum.group_by(declarations, &elem(&1, 0), &elem(&1, 1))}
    end)
  end
end
