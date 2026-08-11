defmodule Hologram.Policy.Compiler do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Reflection

  @doc """
  Builds the compiled policy of the given entity type: a map of operation to the list of rules granting it, in declaration order.

  The grant store's own policy is framework-supplied rather than declared: a user always sees
  the grants they hold, and sees others' grants on a resource when they hold one of that entity
  type's read-grants roles.

  A rule holds the predicate triples of its allow line, its grant references, and its delegation.
  Predicates carry the actor sentinel in value position where the declaration called user_id().
  Grant references are extends-expanded, so a reference to a role also names every role carrying it:
  own roles as {:own, role names}, another entity type's roles as {:type, entity type, role names},
  a related instance's roles as {:rel, relationship name, role names}, and global role modules as
  {:global, role modules} - nil when the line has none.
  A rule grants its operation when its predicates hold, one of its grant references is held, and its
  delegation grants the same operation - and a policy grants its operation when any of its rules does.
  """
  @spec build(module) :: %{
          atom => list(%{predicates: list(tuple), to: list(tuple) | nil, via: atom | nil})
        }
  def build(RoleGrant), do: %{read: role_grant_read_rules()}

  def build(entity_type) do
    entity_type.__policies__()
    |> Enum.map(fn {operation, to, via, predicates} ->
      rule = %{
        predicates: Query.predicate_triples!(entity_type, predicates),
        to: build_to(entity_type, to),
        via: via
      }

      {operation, rule}
    end)
    |> Enum.group_by(fn {operation, _rule} -> operation end, fn {_operation, rule} -> rule end)
  end

  @doc """
  Returns the global roles the given entity type modules declare in more than one OTP app, sorted.

  Each entry pairs the role name with the sorted apps declaring it. Same-name global roles are one
  role across every app behind an endpoint, so a name declared in several of them names one role,
  granted once and held everywhere. Entity types whose OTP app cannot be resolved are skipped.
  """
  @spec cross_app_global_roles(list(module)) :: list({atom, list(atom)})
  def cross_app_global_roles(entity_types) do
    entity_types
    |> Enum.flat_map(&global_role_declarations/1)
    |> Enum.group_by(fn {role_name, _app} -> role_name end, fn {_role_name, app} -> app end)
    |> Enum.map(fn {role_name, apps} ->
      declaring_apps =
        apps
        |> Enum.uniq()
        |> Enum.sort()

      {role_name, declaring_apps}
    end)
    |> Enum.filter(fn {_role_name, apps} -> length(apps) > 1 end)
    |> Enum.sort()
  end

  @doc """
  Returns the given entity type modules that declare no allow lines, sorted.

  Such an entity type is statically dead under default deny - every query against it returns
  nothing, whatever the acting user holds. The grant store is never listed: its policy is
  framework-supplied rather than declared.
  """
  @spec dead_entity_types(list(module)) :: list(module)
  def dead_entity_types(entity_types) do
    entity_types
    |> Enum.filter(&(&1 != RoleGrant and &1.__policies__() == []))
    |> Enum.sort_by(&inspect/1)
  end

  @doc """
  Returns the names of the roles declared with scope :global across the data model, sorted.

  A global role is granted without a resource, and the same name declared on several entity
  types is one role.
  """
  @spec global_role_names() :: list(atom)
  def global_role_names do
    Reflection.list_entities()
    |> Enum.flat_map(&global_role_names/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns the own roles qualifying their holders to manage the grants of the given entity type, sorted.

  These are the extends-expanded own roles of its allow :manage_roles rules - empty when the entity
  type declares none, which leaves granting on it to the trusted tier.
  """
  @spec manage_roles_qualifying_roles(module) :: list(atom)
  def manage_roles_qualifying_roles(entity_type) do
    own_role_names(entity_type, :manage_roles)
  end

  @doc """
  Returns the own roles whose holders see the grants others hold on the given entity type, sorted.

  These are the extends-expanded own roles of its allow :read_grants rules, defaulting to the roles
  qualifying to manage grants when the entity type declares no read_grants rule.
  """
  @spec read_grants_roles(module) :: list(atom)
  def read_grants_roles(entity_type) do
    case own_role_names(entity_type, :read_grants) do
      [] -> manage_roles_qualifying_roles(entity_type)
      role_names -> role_names
    end
  end

  @doc """
  Validates the policy declarations of the given entity type modules as a whole.

  Returns :ok, or raises Hologram.CompileError naming the first invalid declaration.
  Policy declarations are checked here rather than when they are declared, because they are validated against compiled reflection - neither the declaring module nor the entity types it references are compiled while its body is executing.
  """
  @spec validate_model!(list(module)) :: :ok
  def validate_model!(entity_types) do
    validate_role_modules!(Reflection.list_roles())
    validate_user_entity!(entity_types)

    Enum.each(entity_types, fn entity_type ->
      Enum.each(entity_type.__policies__(), fn {operation, to, via, predicates} ->
        validate_to!(entity_type, operation, to)
        validate_via!(entity_type, operation, via)
        validate_predicates!(entity_type, operation, predicates)
      end)
    end)

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

  defp build_global_reference([]), do: []

  defp build_global_reference(role_modules) do
    expanded_modules =
      role_modules
      |> Enum.flat_map(&expand_global_role/1)
      |> Enum.uniq()
      |> Enum.sort()

    [{:global, expanded_modules}]
  end

  defp build_own_reference(_entity_type, []), do: []

  defp build_own_reference(entity_type, role_names) do
    expanded_names =
      role_names
      |> Enum.flat_map(&Entity.expand_role(entity_type, &1))
      |> Enum.uniq()
      |> Enum.sort()

    [{:own, expanded_names}]
  end

  defp build_to(_entity_type, nil), do: nil

  defp build_to(entity_type, to) do
    references = List.wrap(to)

    {role_modules, plain_references} = Enum.split_with(references, &Reflection.alias?/1)
    {role_names, typed_references} = Enum.split_with(plain_references, &is_atom/1)

    own_reference = build_own_reference(entity_type, role_names)
    typed = Enum.map(typed_references, &build_typed_reference(entity_type, &1))
    global_reference = build_global_reference(role_modules)

    own_reference ++ typed ++ global_reference
  end

  defp build_typed_reference(entity_type, {reference, role_name}) do
    if Reflection.alias?(reference) do
      {:type, reference, Entity.expand_role(reference, role_name)}
    else
      target_type = relationship_target(entity_type, reference)

      {:rel, reference, Entity.expand_role(target_type, role_name)}
    end
  end

  # Rotates the cycle to start at its alphabetically first entity type, so that the same
  # cycle is always reported with the same hop order regardless of where traversal entered it.
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

  defp describe_via_cycle([{first_entity_type, _first_relationship_name} | _later_hops] = cycle) do
    hops =
      Enum.map_join(cycle, " -> ", fn {entity_type, relationship_name} ->
        "#{inspect(entity_type)} (via #{inspect(relationship_name)})"
      end)

    "  * #{hops} -> #{inspect(first_entity_type)}"
  end

  # Depth-first traversal over the delegation edges of one operation. The path holds the hops
  # taken to reach the current entity type (most recent first) - reaching an entity type
  # already on the path closes a cycle. Fully explored entity types are marked visited and
  # never re-entered, so each cycle is reported once.
  # A reference to a role module is satisfied by every role carrying it - the module itself and
  # every role whose extends chain reaches it. The sweep is model-wide: role modules resolve
  # globally, so a reference means the same thing in every entity type.
  defp expand_global_role(role_module) do
    extends_by_module =
      Map.new(Reflection.list_roles(), fn module -> {module, module.__extends__()} end)

    expand_global_role_modules(MapSet.new([role_module]), extends_by_module)
  end

  defp expand_global_role_modules(modules, extends_by_module) do
    expanded =
      Enum.reduce(extends_by_module, modules, fn {module, targets}, acc ->
        if Enum.any?(targets, &MapSet.member?(modules, &1)) do
          MapSet.put(acc, module)
        else
          acc
        end
      end)

    if MapSet.size(expanded) == MapSet.size(modules) do
      Enum.sort(expanded)
    else
      expand_global_role_modules(expanded, extends_by_module)
    end
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

  defp global_role_declarations(entity_type) do
    case Application.get_application(entity_type) do
      nil ->
        []

      app ->
        entity_type
        |> global_role_names()
        |> Enum.map(&{&1, app})
    end
  end

  defp global_role_names(entity_type) do
    entity_type.__roles__()
    |> Enum.filter(fn {_name, opts} -> Keyword.get(opts, :scope) == :global end)
    |> Enum.map(fn {name, _opts} -> name end)
  end

  defp own_reference_names(%{to: nil}), do: []

  defp own_reference_names(%{to: references}) do
    Enum.flat_map(references, fn
      {:own, role_names} -> role_names
      _other_reference -> []
    end)
  end

  defp own_role_names(entity_type, operation) do
    entity_type
    |> build()
    |> Map.get(operation, [])
    |> Enum.flat_map(&own_reference_names/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Everyone sees the grants they hold. Seeing someone else's grants on a resource takes one of
  # that resource type's read-grants roles, held on the very resource the grant row names - so
  # the check reads grant rows through grant rows, never through this policy again.
  defp role_grant_read_rules do
    resource_rules =
      Reflection.list_entities()
      |> Enum.reject(&(&1 == RoleGrant))
      |> Enum.map(&{&1, read_grants_roles(&1)})
      |> Enum.reject(fn {_entity_type, role_names} -> role_names == [] end)
      |> Enum.sort_by(fn {entity_type, _role_names} -> RoleGrant.resource_type(entity_type) end)
      |> Enum.map(&role_grant_resource_rule/1)

    [%{predicates: [{:user_id, :==, {:actor}}], to: nil, via: nil} | resource_rules]
  end

  defp role_grant_resource_rule({entity_type, role_names}) do
    %{
      predicates: [{:resource_type, :==, RoleGrant.resource_type(entity_type)}],
      to: [{:resource, entity_type, role_names}],
      via: nil
    }
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

  defp validate_predicates!(entity_type, operation, predicates) do
    Query.predicate_triples!(entity_type, predicates)

    :ok
  rescue
    error in ArgumentError ->
      message =
        "invalid predicate for allow #{inspect(operation)} in #{inspect(entity_type)} - #{Exception.message(error)}"

      reraise Hologram.CompileError, [message: message], __STACKTRACE__
  end

  defp validate_relationship_reference!(entity_type, operation, relationship_name, role_name) do
    definitions = entity_type.__relationships__()

    case Enum.find(definitions, fn {name, _type, _opts} -> name == relationship_name end) do
      {_name, [_target], _opts} ->
        raise Hologram.CompileError,
          message:
            "invalid to option #{inspect({relationship_name, role_name})} for allow #{inspect(operation)} in #{inspect(entity_type)} - relationship #{inspect(relationship_name)} is to-many, but a role reference requires a to-one relationship"

      {_name, target, _opts} ->
        validate_target_role!(entity_type, operation, target, role_name)

      nil ->
        declared_relationships =
          Enum.map_join(definitions, ", ", fn {name, _type, _opts} -> inspect(name) end)

        raise Hologram.CompileError,
          message:
            "unknown relationship #{inspect(relationship_name)} in the to option of allow #{inspect(operation)} in #{inspect(entity_type)} - declared relationships are: #{declared_relationships}"
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

  defp validate_target_role!(entity_type, operation, target_type, role_name) do
    declared_names = declared_role_names(target_type)

    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in the to option of allow #{inspect(operation)} in #{inspect(entity_type)} - declared roles of #{inspect(target_type)} are: #{declared_roles}"
    end
  end

  defp validate_to!(_entity_type, _operation, nil), do: :ok

  defp validate_to!(entity_type, operation, to) do
    if not to_value_valid?(to) do
      raise Hologram.CompileError,
        message:
          "invalid to option #{inspect(to)} for allow #{inspect(operation)} in #{inspect(entity_type)} - the to option must be a role name, a {module, role} or {relationship, role} tuple, or a non-empty list of them"
    end

    to
    |> List.wrap()
    |> Enum.each(&validate_to_reference!(entity_type, operation, &1))
  end

  defp validate_to_reference!(entity_type, operation, {reference, role_name}) do
    if Reflection.alias?(reference) do
      validate_type_reference!(entity_type, operation, reference, role_name)
    else
      validate_relationship_reference!(entity_type, operation, reference, role_name)
    end
  end

  defp validate_to_reference!(entity_type, operation, role_module)
       when is_atom(role_module) do
    if Reflection.alias?(role_module) do
      validate_global_reference!(entity_type, operation, role_module)
    else
      validate_own_reference!(entity_type, operation, role_module)
    end
  end

  defp validate_global_reference!(entity_type, operation, role_module) do
    if not Reflection.role?(role_module) do
      raise Hologram.CompileError,
        message:
          "invalid to option #{inspect(role_module)} for allow #{inspect(operation)} in #{inspect(entity_type)} - #{inspect(role_module)} is not a role module (define it with use Hologram.Role)"
    end
  end

  defp validate_own_reference!(entity_type, operation, role_name) do
    declared_names = declared_role_names(entity_type)

    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in the to option of allow #{inspect(operation)} in #{inspect(entity_type)} - declared roles are: #{declared_roles}"
    end
  end

  defp validate_type_reference!(entity_type, operation, target_type, role_name) do
    if not Reflection.entity?(target_type) do
      raise Hologram.CompileError,
        message:
          "invalid to option #{inspect({target_type, role_name})} for allow #{inspect(operation)} in #{inspect(entity_type)} - #{inspect(target_type)} is not an entity type module"
    end

    validate_target_role!(entity_type, operation, target_type, role_name)
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

  defp validate_via!(_entity_type, _operation, nil), do: :ok

  defp validate_via!(entity_type, operation, via) do
    if not is_atom(via) do
      raise Hologram.CompileError,
        message:
          "invalid via option #{inspect(via)} for allow #{inspect(operation)} in #{inspect(entity_type)} - the via option must be a relationship name"
    end

    definitions = entity_type.__relationships__()

    case Enum.find(definitions, fn {name, _type, _opts} -> name == via end) do
      {_name, [_target], _opts} ->
        raise Hologram.CompileError,
          message:
            "invalid via option #{inspect(via)} for allow #{inspect(operation)} in #{inspect(entity_type)} - relationship #{inspect(via)} is to-many, but delegation requires a to-one relationship"

      {_name, _target, _opts} ->
        :ok

      nil ->
        declared_relationships =
          Enum.map_join(definitions, ", ", fn {name, _type, _opts} -> inspect(name) end)

        raise Hologram.CompileError,
          message:
            "unknown relationship #{inspect(via)} in the via option of allow #{inspect(operation)} in #{inspect(entity_type)} - declared relationships are: #{declared_relationships}"
    end
  end

  defp validate_via_cycles!(entity_types) do
    entity_types
    |> via_edges()
    |> Enum.each(fn {operation, action_edges} ->
      validate_via_cycles!(operation, action_edges)
    end)
  end

  defp validate_via_cycles!(operation, action_edges) do
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
          "cyclic policy delegation for allow #{inspect(operation)} - a via chain can't return to the entity type it starts from:\n#{descriptions}"
    end
  end

  defp via_declarations(entity_type) do
    entity_type.__policies__()
    |> Enum.reject(fn {_operation, _to, via, _predicates} -> is_nil(via) end)
    |> Enum.map(fn {operation, _to, via, _predicates} ->
      {operation, entity_type, {via, relationship_target(entity_type, via)}}
    end)
  end

  # Delegation edges grouped as %{operation => %{entity type => [{relationship name, target type}]}} -
  # a via chain delegates the SAME operation, so each operation forms its own independent graph.
  defp via_edges(entity_types) do
    entity_types
    |> Enum.flat_map(&via_declarations/1)
    |> Enum.group_by(
      fn {operation, _entity_type, _edge} -> operation end,
      fn {_operation, entity_type, edge} -> {entity_type, edge} end
    )
    |> Map.new(fn {operation, declarations} ->
      {operation, Enum.group_by(declarations, &elem(&1, 0), &elem(&1, 1))}
    end)
  end
end
