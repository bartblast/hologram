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
  @spec diff(%{atom => map}, %{atom => map}) :: %{atom => any}
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

    class_plan(add_ops, change_ops, delete_ops, deleted, added, question_fun)
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
        created: created,
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
end
