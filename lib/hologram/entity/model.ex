defmodule Hologram.Entity.Model do
  @moduledoc false

  alias Hologram.Auth.RoleGrant

  # Flag options, whose false is neutral. The option-introduction rule: no option may
  # give nil (or false, for flags) a meaning distinct from absence - every option
  # decides its neutral value at introduction, and normalization collapses neutrals to
  # absence, so two spellings of one model always produce one term. Value options treat
  # nil as neutral uniformly (default: false stays - a boolean default of false is a
  # real default, not a flag).
  @flag_opts [:creator, :optional, :server_only]

  @doc """
  Returns the empty model term - a model with no entity types and no global roles.
  """
  @spec empty() :: %{atom => map}
  def empty, do: %{entities: %{}, roles: %{}}

  @doc """
  Returns the model term derived from the given entity type modules and global role
  modules.

  The term carries declared facts only: :entities maps each entity type module to its
  :attributes, :relationships, and :roles in the reflection tuple shapes, and :roles maps
  each global role module to its :extends list. Members are sorted by name and every opts
  keyword list is sorted by key, so two terms describing the same model always compare
  equal.

  The role grant store is left out - it is derived from the rest of the model rather than
  declared (its enum values are the entity table names and role names), so it is computed
  when the physical mapping is derived, at any point in history.
  """
  @spec from_modules(list(module), list(module)) :: %{atom => map}
  def from_modules(entity_types, role_modules \\ []) do
    entities =
      entity_types
      |> Enum.reject(&(&1 == RoleGrant))
      |> Map.new(fn entity_type ->
        entry = %{
          attributes: normalize_members(entity_type.__attributes__()),
          relationships: normalize_members(entity_type.__relationships__()),
          roles: normalize_roles(entity_type.__roles__())
        }

        {entity_type, entry}
      end)

    roles = Map.new(role_modules, &{&1, %{extends: Enum.sort(&1.__extends__())}})

    %{entities: entities, roles: roles}
  end

  @doc """
  Returns the given model term with the given migration ops applied, in order.

  Replaying a history from empty/0 reconstructs the model as it stood at that point,
  which is what lets a migration file be rendered long after the modules it names are
  gone. An op that contradicts the model it is applied to raises - a delete of an entity
  type that is not there, a create of one that already is - and so does an unresolved
  draft op, which has no meaning to replay.
  """
  @spec fold(%{atom => map}, list(%{atom => any})) :: %{atom => map}
  def fold(model, ops) do
    Enum.reduce(ops, model, &apply_op/2)
  end

  defp apply_op(%{op: :add_attribute} = op, model) do
    add_member(model, op.entity, :attributes, "attribute", {op.name, op.type, op.opts})
  end

  defp apply_op(%{op: :add_relationship} = op, model) do
    add_member(model, op.entity, :relationships, "relationship", {op.name, op.type, op.opts})
  end

  defp apply_op(%{op: :add_role, entity: _entity} = op, model) do
    add_member(model, op.entity, :roles, "role", {op.name, op.opts})
  end

  defp apply_op(%{op: :change_attribute} = op, model) do
    update_member(
      model,
      op.entity,
      :attributes,
      "attribute",
      op.name,
      &change_attribute_member(&1, op)
    )
  end

  defp apply_op(%{op: :change_relationship} = op, model) do
    update_member(model, op.entity, :relationships, "relationship", op.name, fn
      {name, type, opts} ->
        new_type = Keyword.get(op.changes, :type, type)
        new_opts = Keyword.merge(opts, Keyword.delete(op.changes, :type))

        {name, new_type, normalize_opts(new_opts)}
    end)
  end

  defp apply_op(%{op: :change_role, entity: _entity} = op, model) do
    update_member(model, op.entity, :roles, "role", op.name, fn {name, opts} ->
      {name, normalize_opts(Keyword.merge(opts, op.changes))}
    end)
  end

  defp apply_op(%{op: :create_entity} = op, model) do
    validate_absent!(model, op.entity)

    entry = %{attributes: [], relationships: [], roles: []}

    put_in(model, [:entities, op.entity], entry)
  end

  defp apply_op(%{op: :delete_attribute} = op, model) do
    delete_member(model, op.entity, :attributes, "attribute", op.name)
  end

  defp apply_op(%{op: :delete_entity} = op, model) do
    fetch_entity!(model, op.entity)

    update_in(model, [:entities], &Map.delete(&1, op.entity))
  end

  defp apply_op(%{op: :delete_relationship} = op, model) do
    delete_member(model, op.entity, :relationships, "relationship", op.name)
  end

  defp apply_op(%{op: :delete_role, entity: _entity} = op, model) do
    delete_member(model, op.entity, :roles, "role", op.name)
  end

  defp apply_op(%{op: :rename_attribute} = op, model) do
    rename_member(model, op.entity, :attributes, "attribute", op.from, op.to)
  end

  defp apply_op(%{op: :rename_entity} = op, model) do
    entry = fetch_entity!(model, op.from)
    validate_absent!(model, op.to)

    entities =
      model.entities
      |> Map.delete(op.from)
      |> Map.put(op.to, entry)
      |> Map.new(fn {entity_type, entry} -> {entity_type, retarget(entry, op.from, op.to)} end)

    %{model | entities: entities}
  end

  defp apply_op(%{op: :rename_relationship} = op, model) do
    rename_member(model, op.entity, :relationships, "relationship", op.from, op.to)
  end

  defp apply_op(%{op: :rename_role, entity: _entity} = op, model) do
    rename_member(model, op.entity, :roles, "role", op.from, op.to)
  end

  defp apply_op(%{op: :resolve!} = op, _model) do
    raise Hologram.CompileError,
      message:
        "unresolved resolve! op at line #{op.line} - " <>
          "a draft migration is resolved by hand before it can be replayed"
  end

  defp add_member(model, entity_type, list_key, kind, member) do
    name = elem(member, 0)
    members = members!(model, entity_type, list_key)

    if member?(members, name) do
      raise_member_exists!(kind, name, entity_type)
    end

    put_members(model, entity_type, list_key, [normalize_member(member) | members])
  end

  defp change_attribute_member({name, type, opts}, op) do
    new_type = Keyword.get(op.changes, :type, type)

    validate_values_change!(op, type, new_type)

    new_opts =
      opts
      |> Keyword.merge(Keyword.delete(op.changes, :type))
      |> prune_values(new_type)

    validate_enum_values!(op, new_type, new_opts)

    {name, new_type, normalize_opts(new_opts)}
  end

  defp delete_member(model, entity_type, list_key, kind, name) do
    members = members!(model, entity_type, list_key)

    if not member?(members, name) do
      raise_no_member!(kind, name, entity_type)
    end

    put_members(model, entity_type, list_key, Enum.reject(members, &(elem(&1, 0) == name)))
  end

  defp fetch_entity!(model, entity_type) do
    case Map.fetch(model.entities, entity_type) do
      {:ok, entry} ->
        entry

      :error ->
        raise Hologram.CompileError,
          message: "no such entity #{inspect(entity_type)} at this point in migration history"
    end
  end

  defp member?(members, name) do
    Enum.any?(members, &(elem(&1, 0) == name))
  end

  defp members!(model, entity_type, list_key) do
    model
    |> fetch_entity!(entity_type)
    |> Map.fetch!(list_key)
  end

  defp normalize_member({name, type, opts}), do: {name, type, normalize_opts(opts)}

  defp normalize_member({name, opts}), do: {name, normalize_opts(opts)}

  defp normalize_members(members) do
    members
    |> Enum.map(&normalize_member/1)
    |> Enum.sort()
  end

  defp normalize_opts(opts) do
    opts
    |> Enum.reject(fn {key, value} -> is_nil(value) or (value == false and key in @flag_opts) end)
    |> Enum.sort()
  end

  defp normalize_roles(roles) do
    roles
    |> Enum.map(&normalize_member/1)
    |> Enum.sort()
  end

  defp prune_values(opts, :enum), do: opts

  defp prune_values(opts, _type), do: Keyword.delete(opts, :values)

  defp put_members(model, entity_type, list_key, members) do
    put_in(model, [:entities, entity_type, list_key], Enum.sort(members))
  end

  defp raise_member_exists!(kind, name, entity_type) do
    raise Hologram.CompileError,
      message:
        "#{kind} #{inspect(name)} already exists on #{inspect(entity_type)} " <>
          "at this point in migration history"
  end

  defp raise_no_member!(kind, name, entity_type) do
    raise Hologram.CompileError,
      message:
        "no such #{kind} #{inspect(name)} on #{inspect(entity_type)} " <>
          "at this point in migration history"
  end

  defp rename_member(model, entity_type, list_key, kind, from, to) do
    members = members!(model, entity_type, list_key)

    if not member?(members, from) do
      raise_no_member!(kind, from, entity_type)
    end

    if member?(members, to) do
      raise_member_exists!(kind, to, entity_type)
    end

    renamed =
      Enum.map(members, fn member ->
        if elem(member, 0) == from, do: put_elem(member, 0, to), else: member
      end)

    put_members(model, entity_type, list_key, renamed)
  end

  # A renamed entity type is still the target of every relationship that pointed at it,
  # so the new name replaces the old one across the whole term.
  defp retarget(entry, from, to) do
    relationships =
      Enum.map(entry.relationships, fn
        {name, ^from, opts} -> {name, to, opts}
        {name, [^from], opts} -> {name, [to], opts}
        relationship -> relationship
      end)

    %{entry | relationships: relationships}
  end

  defp update_member(model, entity_type, list_key, kind, name, fun) do
    members = members!(model, entity_type, list_key)

    if not member?(members, name) do
      raise_no_member!(kind, name, entity_type)
    end

    updated =
      Enum.map(members, fn member ->
        if elem(member, 0) == name, do: fun.(member), else: member
      end)

    put_members(model, entity_type, list_key, updated)
  end

  defp validate_absent!(model, entity_type) do
    if Map.has_key?(model.entities, entity_type) do
      raise Hologram.CompileError,
        message:
          "entity #{inspect(entity_type)} already exists at this point in migration history"
    end
  end

  defp validate_enum_values!(op, :enum, opts) do
    if opts[:values] in [nil, []] do
      raise Hologram.CompileError,
        message:
          "changing attribute #{inspect(op.name)} on #{inspect(op.entity)} " <>
            "to :enum requires values:"
    end
  end

  defp validate_enum_values!(_op, _type, _opts), do: :ok

  # The rename-vs-replace footgun guard: writing a new value list is never a legal
  # move - the only exception is a type change TO :enum, which must bring the initial
  # values.
  defp validate_values_change!(op, old_type, new_type) do
    becoming_enum? = old_type != :enum and new_type == :enum

    if Keyword.has_key?(op.changes, :values) and not becoming_enum? do
      raise Hologram.CompileError,
        message:
          "enum values change through add_enum_value, rename_enum_value, " <>
            "delete_enum_value, or reorder_enum_values - change_attribute never " <>
            "carries values:"
    end
  end
end
