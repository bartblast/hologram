defmodule Hologram.Policy.Validator do
  @moduledoc false

  alias Hologram.Entity
  alias Hologram.Policy
  alias Hologram.Query.Stage
  alias Hologram.Reflection

  # The operations gating the grant lifecycle. Their checks run without the row in hand -
  # grant_role/revoke_role know the entity type and the entity id, not the row's data - so
  # only own role references can be honored, and anything else would be silently ignored.
  @gate_operations [:grant_role, :read_roles, :revoke_role]

  # The two gate operations that may name the role (or roles) they cover
  @role_operations [:grant_role, :revoke_role]

  @doc """
  Validates the policy declarations of the given entity type modules and the given global role modules as a whole.

  Returns :ok, or raises Hologram.CompileError naming the first invalid declaration.
  Policy declarations are checked here rather than when they are declared, because they are validated against compiled reflection - neither the declaring module nor the entity types it references are compiled while its body is executing.
  """
  @spec validate_model!(list(module), list(module)) :: :ok
  def validate_model!(entity_types, role_modules) do
    validate_role_modules!(role_modules)
    validate_user_entity!(entity_types)

    Enum.each(entity_types, &validate_entity_policies!/1)

    validate_via_cycles!(entity_types)
  end

  @doc """
  Validates the given global role modules as a whole.

  Returns :ok, or raises Hologram.CompileError naming the first invalid declaration (grant-value length, extends targets, extension cycles).
  Extension is checked here rather than at the declaration, because a role module's extends targets are not compiled while its body is executing.
  """
  @spec validate_role_modules!(list(module)) :: :ok
  def validate_role_modules!(role_modules) do
    Enum.each(role_modules, &validate_role_label!/1)
    Enum.each(role_modules, &validate_role_extends_targets!/1)

    validate_role_extends_cycles!(role_modules)
  end

  # Rotates the cycle to start at its alphabetically first role module, so that the same
  # cycle is always reported with the same hop order regardless of where traversal entered it.
  defp canonicalize_role_cycle(cycle) do
    start_index =
      cycle
      |> Enum.with_index()
      |> Enum.min_by(fn {role_module, _index} -> inspect(role_module) end)
      |> elem(1)

    {hops_before_start, hops_from_start} = Enum.split(cycle, start_index)
    hops_from_start ++ hops_before_start
  end

  # Rotates the cycle to start at its alphabetically first entity type, then operation, so that
  # the same cycle is always reported with the same hop order regardless of where traversal
  # entered it.
  defp canonicalize_via_cycle(cycle) do
    start_index =
      cycle
      |> Enum.with_index()
      |> Enum.min_by(fn {{entity_type, operation, via, _source}, _index} ->
        {inspect(entity_type), operation, inspect(via)}
      end)
      |> elem(1)

    {hops_before_start, hops_from_start} = Enum.split(cycle, start_index)
    hops_from_start ++ hops_before_start
  end

  defp declared_role_names(entity_type) do
    Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)
  end

  # TODO: identity features are detected through declarations only - grant_role and can?
  # callsites are not scanned yet, which the compiler's whole-program call graph analysis covers.
  defp declares_identity_features?(entity_type) do
    entity_type.__roles__() != [] or
      Enum.any?(entity_type.__policies__(), fn {_operation, to, _via, _predicates} ->
        to != nil
      end)
  end

  defp describe_role_cycle([first_role_module | _later_hops] = cycle) do
    hops = Enum.map_join(cycle, " -> ", &inspect/1)

    "  * #{hops} -> #{inspect(first_role_module)}"
  end

  defp describe_via_cycle([{first_entity_type, _operation, _via, _source} | _later_hops] = cycle) do
    hops = Enum.map_join(cycle, " -> ", &describe_via_cycle_hop/1)

    "  * #{hops} -> #{inspect(first_entity_type)}"
  end

  # A hop quotes its via option as written, so a delegation naming its operation shows the
  # operation each hop asks. A hop whose via line the entity type wrote itself reads as it always
  # did, and one taken from a policy names it, so a cycle formed out of a shared delegation says
  # where the line lives.
  defp describe_via_cycle_hop({entity_type, _operation, via, entity_type}) do
    "#{inspect(entity_type)} (via #{inspect(via)})"
  end

  defp describe_via_cycle_hop({entity_type, _operation, via, source}) do
    "#{inspect(entity_type)} (via #{inspect(via)}, from #{inspect(source)})"
  end

  # Depth-first traversal over the extends edges. The path holds the roles walked to reach the
  # current one (most recent first) - reaching a role already on the path closes a cycle.
  # Fully explored roles are marked visited and never re-entered, so each cycle is reported once.
  defp find_role_cycles(role_module, path, {cycles, visited}) do
    if MapSet.member?(visited, role_module) do
      {cycles, visited}
    else
      {cycles, visited} =
        Enum.reduce(role_module.__extends__(), {cycles, visited}, fn target_module, acc ->
          follow_role_edge(role_module, target_module, path, acc)
        end)

      {cycles, MapSet.put(visited, role_module)}
    end
  end

  # Depth-first traversal over the delegation edges. A node is an entity type under one operation,
  # since a delegation leads from the operation of its line to the operation it asks the related
  # row. The path holds the hops taken to reach the current node (most recent first) - reaching a
  # node already on the path closes a cycle. Fully explored nodes are marked visited and never
  # re-entered, so each cycle is reported once.
  defp find_via_cycles({entity_type, operation} = node, path, edges, {cycles, visited}) do
    if MapSet.member?(visited, node) do
      {cycles, visited}
    else
      {cycles, visited} =
        edges
        |> Map.get(node, [])
        |> Enum.reduce({cycles, visited}, fn {via, target_node, source}, acc ->
          follow_via_edge({entity_type, operation, via, source}, target_node, path, edges, acc)
        end)

      {cycles, MapSet.put(visited, node)}
    end
  end

  # The name a gate line's condition names first, read off the data form - an attribute or a path -
  # and a disjunction names what its first alternative does, since or names no attribute. The
  # condition was validated before the gate is judged, so an or: entry holding a list is a
  # disjunction here.
  defp first_predicate_name([]), do: nil

  defp first_predicate_name([
         {:or, [first_alternative | _later_alternatives]} | _later_predicates
       ])
       when is_list(first_alternative),
       do: first_predicate_name(first_alternative)

  defp first_predicate_name([{name, _value} | _later_predicates]), do: name

  # Closes a cycle when the target is already on the path, descends into the target otherwise.
  defp follow_role_edge(role_module, target_module, path, {cycles, visited}) do
    new_path = [role_module | path]

    if target_module in new_path do
      {hops_beyond_target, [target_hop | _earlier_hops]} =
        Enum.split_while(new_path, &(&1 != target_module))

      cycle = [target_hop | Enum.reverse(hops_beyond_target)]

      {[cycle | cycles], visited}
    else
      find_role_cycles(target_module, new_path, {cycles, visited})
    end
  end

  # Closes a cycle when the target is already on the path, descends into the target otherwise.
  defp follow_via_edge(hop, target_node, path, edges, {cycles, visited}) do
    new_path = [hop | path]

    if Enum.any?(new_path, &(hop_node(&1) == target_node)) do
      {hops_beyond_target, [target_hop | _earlier_hops]} =
        Enum.split_while(new_path, &(hop_node(&1) != target_node))

      cycle = [target_hop | Enum.reverse(hops_beyond_target)]

      {[cycle | cycles], visited}
    else
      find_via_cycles(target_node, new_path, edges, {cycles, visited})
    end
  end

  defp gate_operation_reason(operation) do
    "#{inspect(operation)} is checked without loading the row, so it takes own role names and global role modules only"
  end

  defp hop_node({entity_type, operation, _via, _source}), do: {entity_type, operation}

  # A line the entity type wrote itself reads exactly as it always did. One that arrived through
  # a policy names the module whose BODY wrote it - the file the dev has to open - because after
  # composition the entity type's own source may hold no such line at all.
  defp location(entity_type, entity_type), do: inspect(entity_type)

  defp location(entity_type, source), do: "#{inspect(entity_type)}, taken from #{inspect(source)}"

  # Reported for one operation at a time, the alphabetically first among the operations the cycles
  # start from once rotated - one message names one operation, which is what its header says.
  defp raise_via_cycles!(cycles) do
    {operation, operation_cycles} =
      cycles
      |> Enum.map(&canonicalize_via_cycle/1)
      |> Enum.uniq()
      |> Enum.group_by(fn [{_entity_type, operation, _via, _source} | _later_hops] ->
        operation
      end)
      |> Enum.min_by(fn {operation, _operation_cycles} -> operation end)

    descriptions =
      operation_cycles
      |> Enum.sort()
      |> Enum.map_join("\n", &describe_via_cycle/1)

    raise Hologram.CompileError,
      message:
        "cyclic policy delegation for allow #{inspect(operation)} - a via chain can't return to the entity type it starts from:\n#{descriptions}"
  end

  # An attribute of the row as inspect/1 spells it, a path as it is written.
  defp server_only_spelling([name]), do: inspect(name)

  defp server_only_spelling(path), do: Stage.inspect_name(path)

  # A line asks the related type an operation it has to be askable about, the way can? refuses one
  # it is not, so a typo or an operation the type never declares fails the build rather than every
  # check that reaches it. A per-role gate line is left to the gate check, which refuses its via
  # option and says why - asked here, the related type would be judged on a role of the line's own
  # type. A bare gate operation needs no exception, since every type can be asked about it.
  defp validate_delegated_operation!(
         _target_type,
         {name, _roles},
         _via,
         _delegated_operation,
         _location
       )
       when name in @role_operations,
       do: :ok

  defp validate_delegated_operation!(target_type, operation, via, delegated_operation, location) do
    Policy.validate_operation!(target_type, delegated_operation)
  rescue
    error in ArgumentError ->
      message =
        "invalid via option #{inspect(via)} for allow #{inspect(operation)} in #{location} - #{Exception.message(error)}"

      reraise Hologram.CompileError, [message: message], __STACKTRACE__
  end

  defp validate_entity_policies!(entity_type) do
    entity_type.__policies__()
    |> Enum.zip(entity_type.__policy_sources__())
    |> Enum.each(&validate_policy_line!(entity_type, &1))
  end

  defp validate_gate_line!(operation, to, via, predicates, location) do
    references = List.wrap(to)

    # A global role is held app-wide, so it is checked without the row as well - what the gate
    # cannot honor is a reference through the row's data: a relationship or a typed reference.
    Enum.each(references, fn reference ->
      if not is_atom(reference) do
        raise Hologram.CompileError,
          message:
            "invalid to option #{inspect(reference)} for allow #{inspect(operation)} in #{location} - #{gate_operation_reason(operation)}"
      end
    end)

    if via do
      raise Hologram.CompileError,
        message:
          "invalid via option #{inspect(via)} for allow #{inspect(operation)} in #{location} - #{gate_operation_reason(operation)}"
    end

    case first_predicate_name(predicates) do
      nil ->
        :ok

      name ->
        raise Hologram.CompileError,
          message:
            "invalid predicate #{Stage.inspect_name(name)} for allow #{inspect(operation)} in #{location} - #{gate_operation_reason(operation)}"
    end

    # A line naming no own role reads as an unconditional grant and qualifies nobody - the same
    # declaration-versus-effect mismatch the reference check catches, in the fail-closed direction.
    # Checked last, so a line that did name something unusable reports what it named.
    if references == [] do
      raise Hologram.CompileError,
        message:
          "missing to option for allow #{inspect(operation)} in #{location} - #{gate_operation_reason(operation)}"
    end

    :ok
  end

  defp validate_gate_operation!(
         entity_type,
         {name, roles} = operation,
         to,
         via,
         predicates,
         location
       )
       when name in @role_operations do
    roles
    |> List.wrap()
    |> Enum.each(&validate_gate_role!(entity_type, operation, &1, location))

    validate_gate_line!(operation, to, via, predicates, location)
  end

  defp validate_gate_operation!(_entity_type, operation, to, via, predicates, location)
       when operation in @gate_operations do
    validate_gate_line!(operation, to, via, predicates, location)
  end

  defp validate_gate_operation!(_entity_type, _operation, _to, _via, _predicates, _location),
    do: :ok

  defp validate_gate_role!(entity_type, operation, role_name, location) do
    declared_names = declared_role_names(entity_type)

    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in allow #{inspect(operation)} in #{location} - declared roles are: #{declared_roles}"
    end
  end

  defp validate_global_reference!(operation, role_module, location) do
    if not Reflection.role?(role_module) do
      raise Hologram.CompileError,
        message:
          "invalid to option #{inspect(role_module)} for allow #{inspect(operation)} in #{location} - #{inspect(role_module)} is not a role module (define it with use Hologram.Role)"
    end
  end

  defp validate_own_reference!(entity_type, operation, role_name, location) do
    declared_names = declared_role_names(entity_type)

    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in the to option of allow #{inspect(operation)} in #{location} - declared roles are: #{declared_roles}"
    end
  end

  defp validate_policy_line!(entity_type, {{operation, to, via, predicates}, source}) do
    location = location(entity_type, source)

    validate_to!(entity_type, operation, to, location)
    validate_via!(entity_type, operation, via, location)
    validate_predicates!(entity_type, operation, predicates, location)
    validate_gate_operation!(entity_type, operation, to, via, predicates, location)
  end

  defp validate_predicates!(entity_type, operation, predicates, location) do
    clauses = Stage.predicate_triples!(entity_type, predicates)
    validate_server_only_predicates!(entity_type, operation, clauses, location)

    :ok
  rescue
    error in ArgumentError ->
      message =
        "invalid predicate for allow #{inspect(operation)} in #{location} - #{Exception.message(error)}"

      reraise Hologram.CompileError, [message: message], __STACKTRACE__
  end

  defp validate_relationship_reference!(
         entity_type,
         operation,
         relationship_name,
         role_name,
         location
       ) do
    definitions = entity_type.__relationships__()

    case Enum.find(definitions, fn {name, _type, _opts} -> name == relationship_name end) do
      {_name, [_target], _opts} ->
        raise Hologram.CompileError,
          message:
            "invalid to option #{inspect({role_name, relationship_name})} for allow #{inspect(operation)} in #{location} - relationship #{inspect(relationship_name)} is to-many, but a role reference requires a to-one relationship"

      {_name, target, _opts} ->
        validate_target_role!(operation, target, role_name, location)

      nil ->
        declared_relationships =
          Enum.map_join(definitions, ", ", fn {name, _type, _opts} -> inspect(name) end)

        raise Hologram.CompileError,
          message:
            "unknown relationship #{inspect(relationship_name)} in the to option of allow #{inspect(operation)} in #{location} - declared relationships are: #{declared_relationships}"
    end
  end

  defp validate_role_extends_cycles!(role_modules) do
    {cycles, _visited} =
      Enum.reduce(role_modules, {[], MapSet.new()}, fn role_module, acc ->
        find_role_cycles(role_module, [], acc)
      end)

    if cycles != [] do
      descriptions =
        cycles
        |> Enum.map(&canonicalize_role_cycle/1)
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map_join("\n", &describe_role_cycle/1)

      raise Hologram.CompileError,
        message:
          "cyclic role extension - an extends chain can't return to the role it starts from:\n#{descriptions}"
    end

    :ok
  end

  defp validate_role_extends_targets!(role_module) do
    Enum.each(role_module.__extends__(), fn target_module ->
      if not Reflection.role?(target_module) do
        raise Hologram.CompileError,
          message:
            "invalid extends target #{inspect(target_module)} in use Hologram.Role for #{inspect(role_module)} - extends targets must be modules defined with use Hologram.Role"
      end
    end)
  end

  # Role modules are stored as grant values in a Postgres enum, whose labels are capped at 63
  # bytes and silently truncated above it - a truncated label would no longer decode back to
  # the module.
  defp validate_role_label!(role_module) do
    label =
      role_module
      |> Atom.to_string()
      |> String.replace_prefix("Elixir.", "")

    label_size = byte_size(label)

    if label_size > 63 do
      raise Hologram.CompileError,
        message:
          "role module name #{inspect(role_module)} is too long to store as a grant value (#{label_size} bytes, limit 63) - shorten the module name"
    end

    :ok
  end

  # Read predicates may reference server-only attributes: a row reaches the client only after
  # the server's read policy admitted it, and the client cannot write a server-only value, so
  # the row's presence already proves the predicate held - the client never evaluates it.
  # Every other operation is decided locally (can?), which needs the value, so there the
  # reference is rejected.
  defp validate_server_only_predicates!(_entity_type, :read, _clauses, _location), do: :ok

  # A path reads the attribute of the row it leads to, so that row's type says whether the attribute
  # is server-only.
  defp validate_server_only_predicates!(entity_type, operation, clauses, location) do
    clauses
    |> Stage.predicate_references()
    |> Enum.each(fn {relationship_names, name} ->
      subject_type = Entity.path_target(entity_type, relationship_names)

      if name in Entity.server_only_attribute_names(subject_type) do
        spelled =
          relationship_names
          |> Enum.concat([name])
          |> server_only_spelling()

        raise Hologram.CompileError,
          message:
            "invalid predicate #{spelled} for allow #{inspect(operation)} in #{location} - #{spelled} is server_only, and the client cannot decide #{inspect(operation)} locally over a value it never holds. Server-only predicates are legal on allow :read only, where the row's presence already proves them"
      end
    end)
  end

  defp validate_target_role!(operation, target_type, role_name, location) do
    declared_names = declared_role_names(target_type)

    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in the to option of allow #{inspect(operation)} in #{location} - declared roles of #{inspect(target_type)} are: #{declared_roles}"
    end
  end

  defp validate_to!(_entity_type, _operation, nil, _location), do: :ok

  defp validate_to!(entity_type, operation, to, location) do
    to
    |> List.wrap()
    |> Enum.each(&validate_to_reference!(entity_type, operation, &1, location))
  end

  defp validate_to_reference!(entity_type, operation, {role_name, reference}, location) do
    if Reflection.alias?(reference) do
      validate_type_reference!(operation, reference, role_name, location)
    else
      validate_relationship_reference!(entity_type, operation, reference, role_name, location)
    end
  end

  defp validate_to_reference!(entity_type, operation, role_module, location)
       when is_atom(role_module) do
    if Reflection.alias?(role_module) do
      validate_global_reference!(operation, role_module, location)
    else
      validate_own_reference!(entity_type, operation, role_module, location)
    end
  end

  defp validate_type_reference!(operation, target_type, role_name, location) do
    if not Reflection.entity?(target_type) do
      raise Hologram.CompileError,
        message:
          "invalid to option #{inspect({role_name, target_type})} for allow #{inspect(operation)} in #{location} - #{inspect(target_type)} is not an entity type module"
    end

    validate_target_role!(operation, target_type, role_name, location)
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

  defp validate_via!(_entity_type, _operation, nil, _location), do: :ok

  defp validate_via!(entity_type, operation, via, location) do
    if not via_shape?(via) do
      raise Hologram.CompileError,
        message:
          "invalid via option #{inspect(via)} for allow #{inspect(operation)} in #{location} - the via option must be a relationship name or an {operation, relationship} tuple"
    end

    {delegated_operation, [relationship_name]} = Policy.delegation(operation, via)
    definitions = entity_type.__relationships__()

    case Enum.find(definitions, fn {name, _type, _opts} -> name == relationship_name end) do
      {_name, [_target], _opts} ->
        raise Hologram.CompileError,
          message:
            "invalid via option #{inspect(via)} for allow #{inspect(operation)} in #{location} - relationship #{inspect(relationship_name)} is to-many, but delegation requires a to-one relationship"

      {_name, target_type, _opts} ->
        validate_delegated_operation!(target_type, operation, via, delegated_operation, location)

      nil ->
        declared_relationships =
          Enum.map_join(definitions, ", ", fn {name, _type, _opts} -> inspect(name) end)

        raise Hologram.CompileError,
          message:
            "unknown relationship #{inspect(relationship_name)} in the via option of allow #{inspect(operation)} in #{location} - declared relationships are: #{declared_relationships}"
    end
  end

  defp validate_via_cycles!(entity_types) do
    edges = via_edges(entity_types)

    {cycles, _visited} =
      edges
      |> Map.keys()
      |> Enum.reduce({[], MapSet.new()}, fn node, acc ->
        find_via_cycles(node, [], edges, acc)
      end)

    if cycles != [] do
      raise_via_cycles!(cycles)
    end

    :ok
  end

  # The source rides the EDGE rather than being looked up when the cycle is described: by then
  # the hop is only a node and a via option, and an entity type can carry several via lines from
  # different policies.
  defp via_declarations(entity_type) do
    entity_type.__policies__()
    |> Enum.zip(entity_type.__policy_sources__())
    |> Enum.reject(fn {{_operation, _to, via, _predicates}, _source} -> is_nil(via) end)
    |> Enum.map(fn {{operation, _to, via, _predicates}, source} ->
      {delegated_operation, relationship_names} = Policy.delegation(operation, via)
      target_type = Entity.path_target(entity_type, relationship_names)

      {{entity_type, operation}, {via, {target_type, delegated_operation}, source}}
    end)
  end

  # Delegation edges grouped by the node they leave, as
  # %{{entity type, operation} => [{via as written, {target type, operation asked}, source}]} - one
  # graph for every operation, since a delegation naming its operation leads from one operation's
  # rules to another's.
  defp via_edges(entity_types) do
    entity_types
    |> Enum.flat_map(&via_declarations/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # A relationship, or an {operation, relationship} tuple naming the operation with an atom.
  defp via_shape?({operation, relationship_name}) do
    is_atom(operation) and operation not in [nil, true, false] and is_atom(relationship_name)
  end

  defp via_shape?(via), do: is_atom(via)
end
