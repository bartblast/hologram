defmodule Hologram.Migration.Diff do
  @moduledoc false

  alias Hologram.Entity.Model

  @doc """
  Returns the migration plan from the replayed model term to the current one - :ops,
  the unambiguous changes, and :questions, the detected ambiguities whose resolution
  ops are withheld pending a human answer.

  A question carries the detected facts (:kind plus the deleted/created member lists),
  :hints (resolutions that look likely, never auto-selected), and :withheld_ops (the
  no-intent interpretation, emitted only if the human confirms it). Ops carry no lines -
  the generator assigns them at render.
  """
  @spec diff(%{atom => any}, %{atom => any}) :: %{atom => any}
  def diff(replayed, current) do
    {entity_ops, entity_questions} = diff_entities(replayed, current)
    {member_ops, member_questions} = diff_members(replayed, current)
    {role_ops, role_questions} = diff_global_roles(replayed, current)

    %{
      ops: entity_ops ++ member_ops ++ role_ops,
      questions: entity_questions ++ member_questions ++ role_questions
    }
  end

  defp add_role_opts(%{extends: []}), do: []

  defp add_role_opts(%{extends: extends}), do: [extends: extends]

  defp attribute_changes(old_type, new_type, old_opts, new_opts) do
    type_changes = if old_type == new_type, do: [], else: [type: new_type]

    # values: belongs to the enum value ops - the one exception is a type change TO
    # :enum, which must bring the initial value list.
    becoming_enum? = old_type != :enum and new_type == :enum
    excluded_keys = if becoming_enum?, do: [], else: [:values]

    Enum.sort(type_changes ++ opts_delta(old_opts, new_opts, excluded_keys))
  end

  defp attribute_names(entry), do: Enum.map(entry.attributes, &elem(&1, 0))

  defp class_plan(add_ops, change_ops, delete_ops, deleted, added, question_fun) do
    if deleted != [] and added != [] do
      question = question_fun.(add_ops ++ delete_ops)

      {change_ops, [question]}
    else
      {add_ops ++ change_ops ++ delete_ops, []}
    end
  end

  defp creation_ops(entity_type, entry) do
    attribute_ops =
      Enum.map(entry.attributes, fn {name, type, opts} ->
        %{op: :add_attribute, entity: entity_type, name: name, type: type, opts: opts}
      end)

    relationship_ops =
      Enum.map(entry.relationships, fn {name, type, opts} ->
        %{op: :add_relationship, entity: entity_type, name: name, type: type, opts: opts}
      end)

    role_ops =
      Enum.map(entry.roles, fn {name, opts} ->
        %{op: :add_role, entity: entity_type, name: name, opts: opts}
      end)

    [%{op: :create_entity, entity: entity_type} | attribute_ops ++ relationship_ops ++ role_ops]
  end

  defp attribute_change_op(entity_type, old_by_name, {name, new_type, new_opts}) do
    case old_by_name[name] do
      nil ->
        []

      {old_type, old_opts} ->
        changes = attribute_changes(old_type, new_type, old_opts, new_opts)

        if changes == [] do
          []
        else
          [%{op: :change_attribute, entity: entity_type, name: name, changes: changes}]
        end
    end
  end

  defp diff_attributes(entity_type, old_members, new_members) do
    old_names = Enum.map(old_members, &elem(&1, 0))
    new_names = Enum.map(new_members, &elem(&1, 0))
    deleted = old_names -- new_names
    added = new_names -- old_names

    add_ops =
      for {name, type, opts} <- new_members, name in added do
        %{op: :add_attribute, entity: entity_type, name: name, type: type, opts: opts}
      end

    delete_ops = Enum.map(deleted, &%{op: :delete_attribute, entity: entity_type, name: &1})

    old_by_name = Map.new(old_members, fn {name, type, opts} -> {name, {type, opts}} end)
    change_ops = Enum.flat_map(new_members, &attribute_change_op(entity_type, old_by_name, &1))

    enum_plans = Enum.map(new_members, &enum_value_plan(entity_type, old_by_name, &1))

    question_fun = fn withheld_ops ->
      deleted_members = Enum.filter(old_members, &(elem(&1, 0) in deleted))
      added_members = Enum.filter(new_members, &(elem(&1, 0) in added))

      %{
        kind: :attributes,
        entity: entity_type,
        deleted: deleted,
        added: added,
        hints: member_rename_hints(deleted_members, added_members),
        withheld_ops: withheld_ops
      }
    end

    class_plan =
      add_ops
      |> class_plan(change_ops, delete_ops, deleted, added, question_fun)
      |> withhold_unfilled_adds(entity_type)

    merge_plans([class_plan | enum_plans])
  end

  defp diff_entities(replayed, current) do
    deleted = Enum.sort(Map.keys(replayed.entities) -- Map.keys(current.entities))
    created = Enum.sort(Map.keys(current.entities) -- Map.keys(replayed.entities))

    create_ops = Enum.flat_map(created, &creation_ops(&1, current.entities[&1]))
    delete_ops = Enum.map(deleted, &%{op: :delete_entity, entity: &1})

    if deleted != [] and created != [] do
      question = %{
        kind: :entities,
        deleted: deleted,
        added: created,
        hints: entity_rename_hints(deleted, created, replayed, current),
        withheld_ops: create_ops ++ delete_ops
      }

      {[], [question]}
    else
      {create_ops ++ delete_ops, []}
    end
  end

  defp diff_entity_members(entity_type, old_entry, new_entry) do
    plans = [
      diff_attributes(entity_type, old_entry.attributes, new_entry.attributes),
      diff_relationships(entity_type, old_entry.relationships, new_entry.relationships),
      diff_entity_roles(entity_type, old_entry.roles, new_entry.roles)
    ]

    merge_plans(plans)
  end

  defp diff_entity_roles(entity_type, old_members, new_members) do
    old_names = Enum.map(old_members, &elem(&1, 0))
    new_names = Enum.map(new_members, &elem(&1, 0))
    deleted = old_names -- new_names
    added = new_names -- old_names

    add_ops =
      for {name, opts} <- new_members, name in added do
        %{op: :add_role, entity: entity_type, name: name, opts: opts}
      end

    delete_ops = Enum.map(deleted, &%{op: :delete_role, entity: entity_type, name: &1})

    old_by_name = Map.new(old_members)
    change_ops = Enum.flat_map(new_members, &entity_role_change_op(entity_type, old_by_name, &1))

    question_fun = fn withheld_ops ->
      %{
        kind: :roles,
        entity: entity_type,
        deleted: deleted,
        added: added,
        hints: pair_hint(deleted, added),
        withheld_ops: withheld_ops
      }
    end

    class_plan(add_ops, change_ops, delete_ops, deleted, added, question_fun)
  end

  defp diff_global_roles(replayed, current) do
    deleted = Enum.sort(Map.keys(replayed.roles) -- Map.keys(current.roles))
    added = Enum.sort(Map.keys(current.roles) -- Map.keys(replayed.roles))

    surviving =
      replayed.roles
      |> Map.keys()
      |> Enum.filter(&Map.has_key?(current.roles, &1))
      |> Enum.sort()

    add_ops = Enum.map(added, &%{op: :add_role, role: &1, opts: add_role_opts(current.roles[&1])})
    delete_ops = Enum.map(deleted, &%{op: :delete_role, role: &1})

    change_ops =
      for module <- surviving, replayed.roles[module] != current.roles[module] do
        %{
          op: :change_role,
          role: module,
          changes: [extends: extends_delta(current.roles[module])]
        }
      end

    if deleted != [] and added != [] do
      question = %{
        kind: :roles,
        deleted: deleted,
        added: added,
        hints: pair_hint(deleted, added),
        withheld_ops: add_ops ++ delete_ops
      }

      {change_ops, [question]}
    else
      {add_ops ++ change_ops ++ delete_ops, []}
    end
  end

  defp diff_members(replayed, current) do
    surviving =
      replayed.entities
      |> Map.keys()
      |> Enum.filter(&Map.has_key?(current.entities, &1))
      |> Enum.sort()

    Enum.reduce(surviving, {[], []}, fn entity_type, {acc_ops, acc_questions} ->
      {ops, questions} =
        diff_entity_members(
          entity_type,
          replayed.entities[entity_type],
          current.entities[entity_type]
        )

      {acc_ops ++ ops, acc_questions ++ questions}
    end)
  end

  defp diff_relationships(entity_type, old_members, new_members) do
    old_names = Enum.map(old_members, &elem(&1, 0))
    new_names = Enum.map(new_members, &elem(&1, 0))
    deleted = old_names -- new_names
    added = new_names -- old_names

    add_ops =
      for {name, type, opts} <- new_members, name in added do
        %{op: :add_relationship, entity: entity_type, name: name, type: type, opts: opts}
      end

    delete_ops = Enum.map(deleted, &%{op: :delete_relationship, entity: entity_type, name: &1})

    old_by_name = Map.new(old_members, fn {name, type, opts} -> {name, {type, opts}} end)
    change_ops = Enum.flat_map(new_members, &relationship_change_op(entity_type, old_by_name, &1))

    question_fun = fn withheld_ops ->
      deleted_members = Enum.filter(old_members, &(elem(&1, 0) in deleted))
      added_members = Enum.filter(new_members, &(elem(&1, 0) in added))

      %{
        kind: :relationships,
        entity: entity_type,
        deleted: deleted,
        added: added,
        hints: member_rename_hints(deleted_members, added_members),
        withheld_ops: withheld_ops
      }
    end

    class_plan(add_ops, change_ops, delete_ops, deleted, added, question_fun)
  end

  # A created entity type whose attribute name set equals a deleted one's looks like a
  # rename - empty sets stay unpaired, matching nothing is no signal.
  defp entity_rename_hints(deleted, created, replayed, current) do
    for old <- deleted,
        new <- created,
        names = attribute_names(replayed.entities[old]),
        names != [],
        names == attribute_names(current.entities[new]) do
      {:rename, old, new}
    end
  end

  # The replace interpretation of an enum value change: drop what left, add what arrived
  # positioned against the values already in place, and reorder when the surviving
  # values also moved (positions alone cannot express that).
  defp enum_replace_ops(entity_type, attribute, old_values, new_values) do
    deleted = old_values -- new_values
    surviving = old_values -- deleted

    delete_ops =
      Enum.map(deleted, fn value ->
        %{op: :delete_enum_value, entity: entity_type, attribute: attribute, value: value}
      end)

    {add_ops, placed} = enum_add_ops(entity_type, attribute, surviving, new_values)

    reorder_ops =
      if placed == new_values do
        []
      else
        [
          %{
            op: :reorder_enum_values,
            entity: entity_type,
            attribute: attribute,
            values: new_values
          }
        ]
      end

    delete_ops ++ add_ops ++ reorder_ops
  end

  defp enum_add_ops(entity_type, attribute, surviving, new_values) do
    added = Enum.reject(new_values, &(&1 in surviving))

    {reversed_ops, placed} =
      Enum.reduce(added, {[], surviving}, fn value, {ops, placed} ->
        opts = enum_position_opts(value, new_values, placed)

        op = %{
          op: :add_enum_value,
          entity: entity_type,
          attribute: attribute,
          value: value,
          opts: opts
        }

        {[op | ops], place_enum_value(placed, value, opts)}
      end)

    {Enum.reverse(reversed_ops), placed}
  end

  # A new value is placed after the nearest already-placed value preceding it, or before
  # the nearest one following it when it comes first - an all-new list just appends.
  defp enum_position_opts(value, new_values, placed) do
    index = Enum.find_index(new_values, &(&1 == value))
    {preceding, [_value | following]} = Enum.split(new_values, index)

    preceding_ref =
      preceding
      |> Enum.reverse()
      |> Enum.find(&(&1 in placed))

    following_ref = Enum.find(following, &(&1 in placed))

    cond do
      preceding_ref -> [after: preceding_ref]
      following_ref -> [before: following_ref]
      true -> []
    end
  end

  defp enum_value_plan(entity_type, old_by_name, {name, :enum, new_opts}) do
    case old_by_name[name] do
      {:enum, old_opts} ->
        old_values = Keyword.fetch!(old_opts, :values)
        new_values = Keyword.fetch!(new_opts, :values)

        enum_values_plan(entity_type, name, old_values, new_values)

      _other ->
        {[], []}
    end
  end

  defp enum_value_plan(_entity_type, _old_by_name, _member), do: {[], []}

  defp enum_values_plan(entity_type, attribute, old_values, new_values) do
    deleted = old_values -- new_values
    added = new_values -- old_values
    ops = enum_replace_ops(entity_type, attribute, old_values, new_values)

    if deleted != [] and added != [] do
      question = %{
        kind: :enum_values,
        entity: entity_type,
        attribute: attribute,
        deleted: deleted,
        added: added,
        hints: pair_hint(deleted, added),
        withheld_ops: ops
      }

      {[], [question]}
    else
      {ops, []}
    end
  end

  defp entity_role_change_op(entity_type, old_by_name, {name, new_opts}) do
    case old_by_name[name] do
      nil ->
        []

      old_opts ->
        changes = opts_delta(old_opts, new_opts, [])

        if changes == [] do
          []
        else
          [%{op: :change_role, entity: entity_type, name: name, changes: changes}]
        end
    end
  end

  defp extends_delta(%{extends: []}), do: nil

  defp extends_delta(%{extends: extends}), do: extends

  # A deleted and an added member of the same type look like a rename - only when each
  # is the single member of that type on its side, so the pairing is unambiguous.
  defp member_rename_hints(deleted_members, added_members) do
    deleted_by_type = Enum.group_by(deleted_members, &elem(&1, 1))
    added_by_type = Enum.group_by(added_members, &elem(&1, 1))

    deleted_by_type
    |> Enum.flat_map(fn {type, deleted_of_type} ->
      case {deleted_of_type, added_by_type[type]} do
        {[old], [new]} -> [{:rename, elem(old, 0), elem(new, 0)}]
        _other -> []
      end
    end)
    |> Enum.sort()
  end

  defp opts_delta(old_opts, new_opts, excluded_keys) do
    keys = Enum.uniq(Keyword.keys(old_opts) ++ Keyword.keys(new_opts)) -- excluded_keys

    keys
    |> Enum.flat_map(fn key ->
      old_value = Keyword.fetch(old_opts, key)
      new_value = Keyword.fetch(new_opts, key)

      cond do
        old_value == new_value -> []
        new_value == :error -> [{key, Model.neutral_value(key)}]
        true -> [{key, elem(new_value, 1)}]
      end
    end)
    |> Enum.sort()
  end

  defp merge_plans(plans) do
    Enum.reduce(plans, {[], []}, fn {ops, questions}, {acc_ops, acc_questions} ->
      {acc_ops ++ ops, acc_questions ++ questions}
    end)
  end

  defp pair_hint([old], [new]), do: [{:rename, old, new}]

  defp pair_hint(_deleted, _added), do: []

  defp place_enum_value(placed, value, opts) do
    cond do
      opts[:after] ->
        List.insert_at(placed, Enum.find_index(placed, &(&1 == opts[:after])) + 1, value)

      opts[:before] ->
        List.insert_at(placed, Enum.find_index(placed, &(&1 == opts[:before])), value)

      true ->
        List.insert_at(placed, -1, value)
    end
  end

  defp relationship_change_op(entity_type, old_by_name, {name, new_type, new_opts}) do
    case old_by_name[name] do
      nil ->
        []

      {old_type, old_opts} ->
        type_changes = if old_type == new_type, do: [], else: [type: new_type]
        changes = Enum.sort(type_changes ++ opts_delta(old_opts, new_opts, []))

        if changes == [] do
          []
        else
          [%{op: :change_relationship, entity: entity_type, name: name, changes: changes}]
        end
    end
  end

  defp unfilled_add?(%{op: :add_attribute} = op) do
    op.opts[:optional] != true and not Keyword.has_key?(op.opts, :default)
  end

  defp unfilled_add?(_op), do: false

  # An attribute added to an entity the history already carries meets rows that predate
  # it, and a required one leaves them without a value. Which value is the author's to
  # know - the model cannot hold it, and the database it will meet is not the one being
  # generated against - so the op is withheld and asked about, the same way an ambiguous
  # rename is. Entities created in this file are exempt: their table is born empty.
  defp withhold_unfilled_adds({ops, questions}, entity_type) do
    {unfilled, filled} = Enum.split_with(ops, &unfilled_add?/1)

    if unfilled == [] do
      {ops, questions}
    else
      question = %{
        kind: :fill,
        entity: entity_type,
        attributes: Enum.map(unfilled, & &1.name),
        members: Enum.map(unfilled, &{&1.name, &1.type, &1.opts}),
        withheld_ops: unfilled
      }

      {filled, Enum.concat(questions, [question])}
    end
  end
end
