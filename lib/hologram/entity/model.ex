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
end
