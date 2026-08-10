defmodule Hologram.Auth.RoleGrant do
  @moduledoc false

  # The role store: one row per granted role. Grant shapes by nil pattern: an instance
  # grant names a resource type and id, a type-wide grant leaves resource_id nil, and a
  # global grant leaves both nil.
  #
  # This module implements the entity contract by hand instead of through use
  # Hologram.Entity, because three parts of its definition are facts of the app, unknown
  # when the dep compiles: the role enum values (the app's declared role names), the
  # resource_type enum values (the app's entity type names), and the relationship targets
  # (the app's designated user entity type). The reflection functions below compute those
  # facts when called - by then the app is compiled - so every consumer reading entity
  # definitions through the standard reflection interface sees an ordinary, fully
  # resolved definition. Keep the hand-written contract in sync with what use
  # Hologram.Entity generates.

  alias Hologram.DB.Mapper
  alias Hologram.Entity.NotIncluded
  alias Hologram.Reflection

  @resolution_key {__MODULE__, :resolution}

  defstruct created_at: nil,
            granted_by: %NotIncluded{relationship: :granted_by},
            granted_by_id: nil,
            id: nil,
            resource_id: nil,
            resource_type: nil,
            role: nil,
            updated_at: nil,
            user: %NotIncluded{relationship: :user},
            user_id: nil

  @type t :: %__MODULE__{
          created_at: DateTime.t() | nil,
          granted_by: struct | NotIncluded.t() | nil,
          granted_by_id: String.t() | nil,
          id: String.t() | nil,
          resource_id: String.t() | nil,
          resource_type: atom | nil,
          role: atom | nil,
          updated_at: DateTime.t() | nil,
          user: struct | NotIncluded.t(),
          user_id: String.t() | nil
        }

  @doc """
  Returns the list of attribute definitions for the role grant entity type, sorted by attribute name.
  The enum value sets are computed from the compiled data model: resource_type values are the entity type table names, and role values are the union of the declared role names.
  """
  @spec __attributes__() :: list({atom, atom, keyword})
  def __attributes__ do
    [
      {:resource_id, :uuid, [optional: true]},
      {:resource_type, :enum, [values: resolved(:resource_type_values), optional: true]},
      {:role, :enum, [values: resolved(:role_values)]}
    ]
  end

  @doc """
  Returns true to indicate that the callee module is an entity type module.
  """
  @spec __is_hologram_entity__() :: boolean
  def __is_hologram_entity__, do: true

  @doc """
  Returns the list of policy definitions for the role grant entity type.
  Empty - the visibility policy of role grants is framework-supplied, not declared.
  """
  @spec __policies__() :: list({atom, term, atom | nil, keyword})
  def __policies__, do: []

  @doc """
  Returns the list of relationship definitions for the role grant entity type, sorted by relationship name.
  Both targets are the app's designated user entity type, computed from the compiled data model.
  """
  @spec __relationships__() :: list({atom, module, keyword})
  def __relationships__ do
    user_entity = resolved(:user_entity)

    [{:granted_by, user_entity, [optional: true]}, {:user, user_entity, []}]
  end

  @doc """
  Returns the list of role definitions for the role grant entity type.
  Empty - roles are granted on resources, and role grant rows are not resources.
  """
  @spec __roles__() :: list({atom, keyword})
  def __roles__, do: []

  @doc """
  Returns the list of system attribute definitions present on every entity type, sorted by attribute name.
  """
  @spec __system_attributes__() :: list({atom, atom, keyword})
  def __system_attributes__ do
    [{:created_at, :datetime, []}, {:id, :uuid, []}, {:updated_at, :datetime, []}]
  end

  @doc false
  @spec resource_type(module) :: atom
  def resource_type(entity_type) do
    entity_type
    |> Mapper.table_name()
    # The atom set is bounded by the app's entity types, all named at build time.
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> String.to_atom()
  end

  @doc false
  @spec reset_resolution_cache() :: :ok
  def reset_resolution_cache do
    :persistent_term.erase(@resolution_key)

    :ok
  end

  defp build_resolution do
    entity_types = Enum.reject(Reflection.list_entities(), &(&1 == __MODULE__))

    resource_type_values =
      entity_types
      |> Enum.map(&resource_type/1)
      |> Enum.sort()

    role_values =
      entity_types
      |> Enum.flat_map(fn entity_type ->
        Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    %{
      resource_type_values: resource_type_values,
      role_values: role_values,
      user_entity: Reflection.user_entity()
    }
  end

  # The resolution sweeps the app's modules, and definition reads happen per write and per
  # query build - so the computed facts are cached for the lifetime of the runtime, like
  # the physical name mapping. The compiler and the application boot reset the cache, so a
  # recompiled data model is picked up.
  defp resolved(key) do
    case :persistent_term.get(@resolution_key, nil) do
      nil ->
        resolution = build_resolution()
        :persistent_term.put(@resolution_key, resolution)
        Map.fetch!(resolution, key)

      resolution ->
        Map.fetch!(resolution, key)
    end
  end
end
