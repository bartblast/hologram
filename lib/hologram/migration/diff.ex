defmodule Hologram.Migration.Diff do
  @moduledoc false

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
    {role_ops, role_questions} = diff_global_roles(replayed, current)

    %{ops: entity_ops ++ role_ops, questions: entity_questions ++ role_questions}
  end

  defp add_role_opts(%{extends: []}), do: []

  defp add_role_opts(%{extends: extends}), do: [extends: extends]

  defp attribute_names(entry), do: Enum.map(entry.attributes, &elem(&1, 0))

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
        hints: role_rename_hints(deleted, added),
        withheld_ops: add_ops ++ delete_ops
      }

      {change_ops, [question]}
    else
      {add_ops ++ change_ops ++ delete_ops, []}
    end
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

  defp extends_delta(%{extends: []}), do: nil

  defp extends_delta(%{extends: extends}), do: extends

  defp role_rename_hints([old], [new]), do: [{:rename, old, new}]

  defp role_rename_hints(_deleted, _added), do: []
end
