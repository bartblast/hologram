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

  # One-time transition values ride the migration op, never the model: a backfill is
  # what existing rows receive as the column arrives, not something the entity declares.
  @transition_opts [:backfill]

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
  Returns the neutral value of the given option - the value whose meaning equals the
  option's absence: false for flag options, nil for value options.

  The removal spelling of the migration change ops: a change setting an option to its
  neutral value removes it from the term.
  """
  @spec neutral_value(atom) :: false | nil
  def neutral_value(key) when key in @flag_opts, do: false

  def neutral_value(_key), do: nil

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
    folded = Enum.reduce(ops, model, &apply_op/2)
    deleted_types = for %{op: :delete_entity, entity: entity_type} <- ops, do: entity_type
    created_types = for %{op: :create_entity, entity: entity_type} <- ops, do: entity_type

    validate_deleted_targets!(folded, deleted_types)
    validate_filled_adds!(ops, created_types)

    folded
  end

  defp apply_op(%{op: :add_attribute} = op, model) do
    validate_added_enum_values!(op)
    validate_backfill_value!(op)

    add_member(model, op.entity, :attributes, "attribute", {op.name, op.type, op.opts})
  end

  defp apply_op(%{op: :add_enum_value} = op, model) do
    update_enum_attribute(model, op, fn values, opts ->
      if op.value in values do
        raise_enum_value_exists!(op, op.value)
      end

      {insert_enum_value(values, op), opts}
    end)
  end

  defp apply_op(%{op: :add_relationship} = op, model) do
    add_member(model, op.entity, :relationships, "relationship", {op.name, op.type, op.opts})
  end

  defp apply_op(%{op: :add_role, entity: _entity} = op, model) do
    add_member(model, op.entity, :roles, "role", {op.name, op.opts})
  end

  defp apply_op(%{op: :add_role, role: _role} = op, model) do
    if Map.has_key?(model.roles, op.role) do
      raise Hologram.CompileError,
        message: "role #{inspect(op.role)} already exists at this point in migration history"
    end

    extends =
      op.opts
      |> Keyword.get(:extends)
      |> List.wrap()
      |> Enum.sort()

    put_in(model, [:roles, op.role], %{extends: extends})
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

  defp apply_op(%{op: :change_role, role: _role} = op, model) do
    entry = fetch_role!(model, op.role)

    extends =
      op.changes
      |> Keyword.get(:extends, entry.extends)
      |> List.wrap()
      |> Enum.sort()

    put_in(model, [:roles, op.role], %{entry | extends: extends})
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

  defp apply_op(%{op: :delete_enum_value} = op, model) do
    update_enum_attribute(model, op, fn values, opts ->
      if op.value not in values do
        raise_no_enum_value!(op, op.value)
      end

      if opts[:default] == op.value do
        raise Hologram.CompileError,
          message:
            "enum value #{inspect(op.value)} is the default of attribute " <>
              "#{inspect(op.attribute)} on #{inspect(op.entity)} - " <>
              "change the default before deleting the value"
      end

      {values -- [op.value], opts}
    end)
  end

  defp apply_op(%{op: :delete_relationship} = op, model) do
    delete_member(model, op.entity, :relationships, "relationship", op.name)
  end

  defp apply_op(%{op: :delete_role, entity: _entity} = op, model) do
    delete_member(model, op.entity, :roles, "role", op.name)
  end

  defp apply_op(%{op: :delete_role, role: _role} = op, model) do
    fetch_role!(model, op.role)

    extended_by =
      for {module, %{extends: extends}} <- model.roles, op.role in extends, do: module

    if extended_by != [] do
      raise Hologram.CompileError,
        message:
          "role #{inspect(op.role)} is extended by " <>
            "#{Enum.map_join(Enum.sort(extended_by), ", ", &inspect/1)} - " <>
            "delete or change the extending roles first"
    end

    update_in(model, [:roles], &Map.delete(&1, op.role))
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

  defp apply_op(%{op: :rename_enum_value} = op, model) do
    update_enum_attribute(model, op, &rename_enum_value_member(&1, &2, op))
  end

  defp apply_op(%{op: :rename_relationship} = op, model) do
    rename_member(model, op.entity, :relationships, "relationship", op.from, op.to)
  end

  defp apply_op(%{op: :rename_role, entity: _entity} = op, model) do
    rename_member(model, op.entity, :roles, "role", op.from, op.to)
  end

  defp apply_op(%{op: :rename_role, from: _from} = op, model) do
    entry = fetch_role!(model, op.from)

    if Map.has_key?(model.roles, op.to) do
      raise Hologram.CompileError,
        message: "role #{inspect(op.to)} already exists at this point in migration history"
    end

    roles =
      model.roles
      |> Map.delete(op.from)
      |> Map.put(op.to, entry)
      |> Map.new(fn {module, role_entry} ->
        {module, retarget_extends(role_entry, op.from, op.to)}
      end)

    %{model | roles: roles}
  end

  defp apply_op(%{op: :reorder_enum_values} = op, model) do
    update_enum_attribute(model, op, fn values, opts ->
      if Enum.sort(op.values) != Enum.sort(values) do
        raise_not_a_permutation!(op, values)
      end

      {op.values, opts}
    end)
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

  defp describe_enum_values([], _word), do: nil

  defp describe_enum_values([value], word), do: "#{inspect(value)} is #{word}"

  defp describe_enum_values(values, word) do
    "#{Enum.map_join(values, ", ", &inspect/1)} are #{word}"
  end

  defp fetch_role!(model, role) do
    case Map.fetch(model.roles, role) do
      {:ok, entry} ->
        entry

      :error ->
        raise Hologram.CompileError,
          message: "no such role #{inspect(role)} at this point in migration history"
    end
  end

  defp insert_enum_value(values, op) do
    before_ref = Keyword.get(op.opts, :before)
    after_ref = Keyword.get(op.opts, :after)

    cond do
      before_ref && after_ref ->
        raise Hologram.CompileError,
          message: "add_enum_value takes at most one of before: and after:"

      before_ref ->
        List.insert_at(values, position_index!(values, before_ref, op), op.value)

      after_ref ->
        List.insert_at(values, position_index!(values, after_ref, op) + 1, op.value)

      true ->
        List.insert_at(values, -1, op.value)
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
    |> Enum.reject(fn {key, value} ->
      key in @transition_opts or is_nil(value) or (value == false and key in @flag_opts)
    end)
    |> Enum.sort()
  end

  defp normalize_roles(roles) do
    roles
    |> Enum.map(&normalize_member/1)
    |> Enum.sort()
  end

  defp position_index!(values, ref, op) do
    case Enum.find_index(values, &(&1 == ref)) do
      nil -> raise_no_enum_value!(op, ref)
      index -> index
    end
  end

  defp prune_values(opts, :enum), do: opts

  defp prune_values(opts, _type), do: Keyword.delete(opts, :values)

  defp put_members(model, entity_type, list_key, members) do
    put_in(model, [:entities, entity_type, list_key], Enum.sort(members))
  end

  defp raise_enum_value_exists!(op, value) do
    raise Hologram.CompileError,
      message:
        "enum value #{inspect(value)} already exists on attribute #{inspect(op.attribute)} " <>
          "of #{inspect(op.entity)} at this point in migration history"
  end

  defp raise_member_exists!(kind, name, entity_type) do
    raise Hologram.CompileError,
      message:
        "#{kind} #{inspect(name)} already exists on #{inspect(entity_type)} " <>
          "at this point in migration history"
  end

  defp raise_no_enum_value!(op, value) do
    raise Hologram.CompileError,
      message:
        "no such enum value #{inspect(value)} on attribute #{inspect(op.attribute)} " <>
          "of #{inspect(op.entity)} at this point in migration history"
  end

  defp raise_no_member!(kind, name, entity_type) do
    raise Hologram.CompileError,
      message:
        "no such #{kind} #{inspect(name)} on #{inspect(entity_type)} " <>
          "at this point in migration history"
  end

  defp raise_not_a_permutation!(op, current_values) do
    missing = current_values -- op.values
    new = op.values -- current_values

    segments =
      [describe_enum_values(missing, "missing"), describe_enum_values(new, "new")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" and ")

    raise Hologram.CompileError,
      message:
        "reorder_enum_values changes order only - #{segments} - " <>
          "a rename is rename_enum_value, a removal is delete_enum_value, " <>
          "an addition is add_enum_value"
  end

  defp rename_enum_value_member(values, opts, op) do
    if op.from not in values do
      raise_no_enum_value!(op, op.from)
    end

    if op.to in values do
      raise_enum_value_exists!(op, op.to)
    end

    renamed = Enum.map(values, fn value -> if value == op.from, do: op.to, else: value end)

    # The retargeting principle one level down: value-referencing options follow the
    # renamed value, so a rename is always one instruction.
    new_opts = if opts[:default] == op.from, do: Keyword.put(opts, :default, op.to), else: opts

    {renamed, new_opts}
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

  defp retarget_extends(%{extends: extends} = role_entry, from, to) do
    retargeted = Enum.map(extends, fn target -> if target == from, do: to, else: target end)

    %{role_entry | extends: Enum.sort(retargeted)}
  end

  defp update_enum_attribute(model, op, fun) do
    update_member(model, op.entity, :attributes, "attribute", op.attribute, fn
      {name, type, opts} ->
        if type != :enum do
          raise Hologram.CompileError,
            message:
              "attribute #{inspect(op.attribute)} on #{inspect(op.entity)} " <>
                "is not an :enum attribute"
        end

        current_values = Keyword.fetch!(opts, :values)
        {values, new_opts} = fun.(current_values, opts)
        final_opts = Keyword.put(new_opts, :values, values)

        {name, type, normalize_opts(final_opts)}
    end)
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

  defp target_type([target]), do: target

  defp target_type(target), do: target

  defp validate_absent!(model, entity_type) do
    if Map.has_key?(model.entities, entity_type) do
      raise Hologram.CompileError,
        message:
          "entity #{inspect(entity_type)} already exists at this point in migration history"
    end
  end

  # The same requirement change_attribute enforces when a type becomes :enum, at the other
  # door into an enum attribute - without it the values are missing from the model and the
  # first enum op raises a bare KeyError, naming neither the attribute nor its entity.
  defp validate_added_enum_values!(%{type: :enum} = op) do
    if op.opts[:values] in [nil, []] do
      raise Hologram.CompileError,
        message:
          "adding attribute #{inspect(op.name)} to #{inspect(op.entity)} " <>
            "as :enum requires values:"
    end
  end

  defp validate_added_enum_values!(_op), do: :ok

  # A backfill is the value the rows predating the column receive, so nil is not one - it
  # is the absence the backfill exists to fill. Left to run, it reads as a fill to the
  # pre-flight, which then skips the check that would have refused, and the column is
  # tightened over the NULLs it just wrote - a not-null violation from PostgreSQL, mid-apply.
  defp validate_backfill_value!(op) do
    if Keyword.has_key?(op.opts, :backfill) and is_nil(op.opts[:backfill]) do
      raise Hologram.CompileError,
        message:
          "backfill: nil on attribute #{inspect(op.name)} of #{inspect(op.entity)} - " <>
            "a backfill is the value existing rows receive, so it needs one - make the " <>
            "attribute optional: instead, or give the backfill a value"
    end
  end

  # Checked on what the ops leave behind rather than op by op, because their order inside
  # one file is free: deleting the entity before its inbound relationship is fine, and the
  # generator emits exactly that.
  #
  # A reference outliving its target is not merely an odd model. Every model a file leaves
  # behind is applied on its own, and the table cannot be dropped while a foreign key still
  # points at it - PostgreSQL refuses the file mid-deploy, in wording of its own. Refusing
  # while folding moves that to where the history is read: before the boot touches
  # anything, and in a message naming the relationship to delete.
  #
  # Scoped to the types this fold deletes, so a model built around one entity type may
  # still name targets it does not carry.
  defp validate_deleted_targets!(model, deleted_types) do
    dangling =
      for {entity_type, entry} <- model.entities,
          {name, target, _opts} <- entry.relationships,
          target_type(target) in deleted_types do
        "#{inspect(name)} on #{inspect(entity_type)} targets #{inspect(target_type(target))}"
      end

    if dangling != [] do
      raise Hologram.CompileError,
        message:
          "relationship targets deleted at this point in migration history - " <>
            "#{Enum.join(Enum.sort(dangling), ", ")} - delete the relationship in the " <>
            "migration that deletes its target, or an earlier one"
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
  # A required attribute added to a table that already stands meets the rows that predate
  # it, and leaves them without a value - which the apply refuses once it counts them. The
  # value is the author's to supply: the model cannot carry it, and the database this file
  # will meet is not the one it was generated against, so an empty table today proves
  # nothing about the one that runs it next.
  #
  # Entities created by the same ops are exempt - their table is born here, holding nothing.
  defp validate_filled_adds!(ops, created_types) do
    unfilled =
      for %{op: :add_attribute} = op <- ops,
          op.entity not in created_types,
          op.opts[:optional] != true,
          not Keyword.has_key?(op.opts, :default),
          not Keyword.has_key?(op.opts, :backfill) do
        "#{inspect(op.name)} on #{inspect(op.entity)}"
      end

    if unfilled != [] do
      raise Hologram.CompileError,
        message:
          "required attributes added without a value for existing rows - " <>
            "#{Enum.join(Enum.sort(unfilled), ", ")} - add backfill: for a one-time " <>
            "value, default: to give every row one, or optional: to leave them empty"
    end
  end

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
