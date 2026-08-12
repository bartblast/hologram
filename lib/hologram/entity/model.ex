defmodule Hologram.Entity.Model do
  @moduledoc false

  @doc """
  Returns the empty model term - a model with no entity types.
  """
  @spec empty() :: %{module => %{atom => list}}
  def empty, do: %{}

  @doc """
  Returns the model term derived from the given entity type modules.

  The term maps each entity type module to its declarations - :attributes,
  :relationships, and :roles, in the reflection tuple shapes - with members sorted
  by name and every opts keyword list sorted by key, so two terms describing the
  same model always compare equal.
  """
  @spec from_modules(list(module)) :: %{module => %{atom => list}}
  def from_modules(entity_types) do
    Map.new(entity_types, fn entity_type ->
      entry = %{
        attributes: normalize_members(entity_type.__attributes__()),
        relationships: normalize_members(entity_type.__relationships__()),
        roles: normalize_roles(entity_type.__roles__())
      }

      {entity_type, entry}
    end)
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
