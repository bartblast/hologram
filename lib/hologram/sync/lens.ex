defmodule Hologram.Sync.Lens do
  @moduledoc false

  # What a tab built against an older data model calls each thing the current model declares: the
  # name every entity type, attribute, relationship, enum value and role had at the point of the
  # migration history the tab's bundle was built at, or that it is new since. Worked out from the
  # ops of every migration file after that point, walked forward in order, so a chain of several
  # deploys reads as one.
  #
  # Only additions, renames and changes that leave a row's shape as it was can be served: an old
  # tab is then sent the current rows under its own names, with what is new left out. Anything a
  # tab's code could miss - a delete, a type change, an attribute turned server-only or optional -
  # makes the chain unservable, and the tab is told to reload as before.
  #
  # The state is keyed by the names the model has at each step of the walk, and maps each to its
  # name at the tab's point, or :new. A name the walk never touched is absent and means itself, so
  # a chain renaming one attribute costs one entry, whatever the size of the model. The model term
  # at the tab's point answers the two things the ops can't: whether an attribute turned
  # server-only off was server-only for the tab, and which entity type the tab took as its user.

  defstruct global_roles: %{}, types: %{}

  @type old(name) :: name | :new

  @type t :: %__MODULE__{
          global_roles: %{module => old(module)},
          types: %{module => type_entry}
        }

  @type type_entry :: %{
          attributes: %{atom => old(atom)},
          enums: %{atom => %{atom => old(atom)}},
          old: old(module),
          relationships: %{atom => old(atom)},
          roles: %{atom => old(atom)}
        }

  # Changes of an attribute's options that leave every row's shape as an old tab expects it:
  # defaults and bounds are checked on writes, and a column made unique or required keeps the
  # values it held. A fill of the NULLs a required column held changes rows at rest, with nothing
  # in the log to say so, which is the caller's to answer by filling the tab again.
  @attribute_keys_kept [
    :default,
    :format,
    :in,
    :length,
    :max,
    :max_length,
    :min,
    :min_length,
    :unique
  ]

  @relationship_keys_kept [:sort, :unique]

  @role_keys_kept [:extends, :granted_to]

  @doc """
  Returns the lens a tab built at a point of the migration history is served through, given the
  model term at that point (see `Hologram.Entity.Model.fold/3`) and the ops of every migration file
  after it, in order - or `:unservable` when one of them changes something the tab's code reads in
  a way no renaming can give back.

  No ops give the lens that changes nothing.
  """
  @spec build(%{atom => any}, list(map)) :: {:ok, t} | :unservable
  def build(old_model, ops) do
    walked =
      Enum.reduce_while(ops, {%__MODULE__{}, old_model.user_entity}, fn op, {lens, user_entity} ->
        case step(op, lens, user_entity, old_model) do
          {:unservable, _user_entity} -> {:halt, :unservable}
          stepped -> {:cont, stepped}
        end
      end)

    case walked do
      :unservable -> :unservable
      {lens, _user_entity} -> {:ok, lens}
    end
  end

  @doc """
  Returns what the tab calls the given attribute of the given entity type, or :new.
  """
  @spec old_attribute(t, module, atom) :: old(atom)
  def old_attribute(lens, entity_type, name), do: old_member(lens, entity_type, :attributes, name)

  @doc """
  Returns what the tab calls the given value of the given enum attribute of the given entity type,
  or :new - for a value added since, or a value of an attribute or a type added since.
  """
  @spec old_enum_value(t, module, atom, atom) :: old(atom)
  def old_enum_value(lens, entity_type, attribute, value) do
    case old_attribute(lens, entity_type, attribute) do
      :new ->
        :new

      _old_attribute ->
        values = Map.get(type_entry(lens, entity_type).enums, attribute, %{})

        Map.get(values, value, value)
    end
  end

  @doc """
  Returns what the tab calls the given global role module, or :new.
  """
  @spec old_global_role(t, module) :: old(module)
  def old_global_role(lens, role), do: Map.get(lens.global_roles, role, role)

  @doc """
  Returns what the tab calls the given relationship of the given entity type, or :new.
  """
  @spec old_relationship(t, module, atom) :: old(atom)
  def old_relationship(lens, entity_type, name) do
    old_member(lens, entity_type, :relationships, name)
  end

  @doc """
  Returns what the tab calls the given role of the given entity type, or :new.
  """
  @spec old_role(t, module, atom) :: old(atom)
  def old_role(lens, entity_type, name), do: old_member(lens, entity_type, :roles, name)

  @doc """
  Returns what the tab calls the given entity type, or :new.
  """
  @spec old_type(t, module) :: old(module)
  def old_type(lens, entity_type), do: type_entry(lens, entity_type).old

  # The walk keeps the user entity type under its name at each step, beside the lens: a file
  # renaming it can also designate it under its new name, which moves nothing (see
  # `Hologram.Migration.Diff`).
  defp step(%{op: :rename_entity, from: from, to: to} = op, lens, user_entity, old_model) do
    {apply_op(op, lens, old_model), if(user_entity == from, do: to, else: user_entity)}
  end

  defp step(%{op: :designate_user_entity, entity: user_entity}, lens, user_entity, _old_model) do
    {lens, user_entity}
  end

  defp step(op, lens, user_entity, old_model) do
    {apply_op(op, lens, old_model), user_entity}
  end

  defp apply_op(%{op: :create_entity, entity: entity_type}, lens, _old_model) do
    put_type(lens, entity_type, %{new_entry(entity_type) | old: :new})
  end

  defp apply_op(%{op: :rename_entity, from: from, to: to}, lens, _old_model) do
    entry = type_entry(lens, from)
    types = Map.delete(lens.types, from)

    %{lens | types: Map.put(types, to, entry)}
  end

  defp apply_op(%{op: :add_attribute, entity: entity_type, name: name}, lens, _old_model) do
    put_member(lens, entity_type, :attributes, name, :new)
  end

  defp apply_op(
         %{op: :rename_attribute, entity: entity_type, from: from, to: to},
         lens,
         _old_model
       ) do
    update_type(lens, entity_type, fn entry ->
      {enum, enums} = Map.pop(entry.enums, from)
      enums = if enum, do: Map.put(enums, to, enum), else: enums

      %{rename_in(entry, :attributes, from, to) | enums: enums}
    end)
  end

  defp apply_op(%{op: :add_relationship, entity: entity_type, name: name}, lens, _old_model) do
    put_member(lens, entity_type, :relationships, name, :new)
  end

  defp apply_op(
         %{op: :rename_relationship, entity: entity_type, from: from, to: to},
         lens,
         _old_model
       ) do
    update_type(lens, entity_type, &rename_in(&1, :relationships, from, to))
  end

  defp apply_op(%{op: :add_enum_value} = op, lens, _old_model) do
    update_enum(lens, op.entity, op.attribute, &Map.put(&1, op.value, :new))
  end

  defp apply_op(%{op: :rename_enum_value} = op, lens, _old_model) do
    update_enum(lens, op.entity, op.attribute, fn values ->
      {old, values} = Map.pop(values, op.from, op.from)

      Map.put(values, op.to, old)
    end)
  end

  defp apply_op(%{op: :add_role, entity: entity_type, name: name}, lens, _old_model) do
    put_member(lens, entity_type, :roles, name, :new)
  end

  defp apply_op(%{op: :add_role, role: role}, lens, _old_model) do
    %{lens | global_roles: Map.put(lens.global_roles, role, :new)}
  end

  defp apply_op(%{op: :rename_role, entity: entity_type, from: from, to: to}, lens, _old_model) do
    update_type(lens, entity_type, &rename_in(&1, :roles, from, to))
  end

  defp apply_op(%{op: :rename_role, from: from, to: to}, lens, _old_model) do
    {old, global_roles} = Map.pop(lens.global_roles, from, from)

    %{lens | global_roles: Map.put(global_roles, to, old)}
  end

  defp apply_op(%{op: op}, lens, _old_model)
       when op in [:add_unique, :delete_unique, :reorder_enum_values] do
    lens
  end

  defp apply_op(
         %{op: :change_attribute, entity: entity_type, name: name, changes: changes},
         lens,
         old_model
       ) do
    server_only? = server_only_for_tab?(lens, old_model, entity_type, name)

    case worst(Enum.map(changes, &attribute_change(&1, server_only?))) do
      :unservable -> :unservable
      :new -> put_member(lens, entity_type, :attributes, name, :new)
      :kept -> lens
    end
  end

  defp apply_op(%{op: :change_relationship, changes: changes}, lens, _old_model) do
    case worst(Enum.map(changes, &relationship_change/1)) do
      :unservable -> :unservable
      :kept -> lens
    end
  end

  defp apply_op(%{op: :change_role, changes: changes}, lens, _old_model) do
    if Enum.all?(changes, fn {key, _value} -> key in @role_keys_kept end) do
      lens
    else
      :unservable
    end
  end

  # Every delete, a type change, a user designation that moves, arrives or leaves, the grants
  # deleted with it, a draft op, and any op this doesn't know.
  defp apply_op(_op, _lens, _old_model), do: :unservable

  # A flag set to nil is the flag turned off, as the model term reads it.
  defp attribute_change({key, _value}, _server_only?) when key in @attribute_keys_kept, do: :kept

  defp attribute_change({:optional, flag}, _server_only?) when flag in [false, nil], do: :kept

  # An attribute the tab's model keeps from it (see `Hologram.Sync.WireData`): it never had it. One
  # that wasn't server-only for the tab is turned off again, which changes nothing.
  defp attribute_change({:server_only, flag}, server_only?) when flag in [false, nil] do
    if server_only?, do: :new, else: :kept
  end

  defp attribute_change(_change, _server_only?), do: :unservable

  defp new_entry(entity_type) do
    %{attributes: %{}, enums: %{}, old: entity_type, relationships: %{}, roles: %{}}
  end

  defp old_member(lens, entity_type, kind, name) do
    entry = type_entry(lens, entity_type)
    members = Map.fetch!(entry, kind)

    if entry.old == :new, do: :new, else: Map.get(members, name, name)
  end

  # An attribute the tab had can only have become server-only since through a change the walk
  # refuses, so it is server-only for the tab exactly when the tab's model term says so.
  defp server_only_for_tab?(lens, old_model, entity_type, name) do
    with old_type when old_type != :new <- old_type(lens, entity_type),
         old_name when old_name != :new <- old_attribute(lens, entity_type, name),
         %{attributes: attributes} <- Map.get(old_model.entities, old_type) do
      Enum.any?(attributes, fn {attribute, _type, opts} ->
        attribute == old_name and opts[:server_only] == true
      end)
    else
      _new_or_unknown -> false
    end
  end

  defp put_member(lens, entity_type, kind, name, old) do
    update_type(lens, entity_type, &put_in(&1, [kind, name], old))
  end

  defp put_type(lens, entity_type, entry) do
    %{lens | types: Map.put(lens.types, entity_type, entry)}
  end

  defp relationship_change({key, _value}) when key in @relationship_keys_kept, do: :kept

  defp relationship_change({:optional, flag}) when flag in [false, nil], do: :kept

  defp relationship_change(_change), do: :unservable

  defp rename_in(entry, kind, from, to) do
    {old, members} =
      entry
      |> Map.fetch!(kind)
      |> Map.pop(from, from)

    Map.put(entry, kind, Map.put(members, to, old))
  end

  defp type_entry(lens, entity_type) do
    Map.get(lens.types, entity_type, new_entry(entity_type))
  end

  defp update_enum(lens, entity_type, attribute, fun) do
    update_type(lens, entity_type, fn entry ->
      values = Map.get(entry.enums, attribute, %{})

      %{entry | enums: Map.put(entry.enums, attribute, fun.(values))}
    end)
  end

  defp update_type(lens, entity_type, fun) do
    entry = type_entry(lens, entity_type)

    put_type(lens, entity_type, fun.(entry))
  end

  defp worst(answers) do
    cond do
      :unservable in answers -> :unservable
      :new in answers -> :new
      true -> :kept
    end
  end
end
