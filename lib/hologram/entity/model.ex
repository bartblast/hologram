defmodule Hologram.Entity.Model do
  @moduledoc false

  alias Hologram.Auth.RoleGrant

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

  defp apply_op(%{op: :create_entity} = op, model) do
    validate_absent!(model, op.entity)

    entry = %{attributes: [], relationships: [], roles: []}

    put_in(model, [:entities, op.entity], entry)
  end

  defp apply_op(%{op: :delete_entity} = op, model) do
    fetch_entity!(model, op.entity)

    update_in(model, [:entities], &Map.delete(&1, op.entity))
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

  defp apply_op(%{op: :resolve!} = op, _model) do
    raise Hologram.CompileError,
      message:
        "unresolved resolve! op at line #{op.line} - " <>
          "a draft migration is resolved by hand before it can be replayed"
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

  defp normalize_members(members) do
    members
    |> Enum.map(fn {name, type, opts} -> {name, type, Enum.sort(opts)} end)
    |> Enum.sort()
  end

  defp normalize_roles(roles) do
    roles
    |> Enum.map(fn {name, opts} -> {name, Enum.sort(opts)} end)
    |> Enum.sort()
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

  defp validate_absent!(model, entity_type) do
    if Map.has_key?(model.entities, entity_type) do
      raise Hologram.CompileError,
        message:
          "entity #{inspect(entity_type)} already exists at this point in migration history"
    end
  end
end
