defmodule Hologram.Auth.RoleGrant do
  @moduledoc false

  # The role store: one row per granted role. Grant shapes by nil pattern: an instance
  # grant names a resource type and id, a type-wide grant leaves resource_id nil, and a
  # global grant leaves both nil. A row's role is an entity role name (:admin) or a global
  # role module (MyApp.Roles.Admin).
  #
  # This module implements the entity contract by hand instead of through use
  # Hologram.Entity, because three parts of its definition are facts of the app, unknown
  # when the dep compiles: the role enum values (the app's declared role names and global
  # role modules), the
  # resource_type enum values (the app's entity type names), and the relationship targets
  # (the app's designated user entity type). The reflection functions below compute those
  # facts when called - by then the app is compiled - so every consumer reading entity
  # definitions through the standard reflection interface sees an ordinary, fully
  # resolved definition. Keep the hand-written contract in sync with what use
  # Hologram.Entity generates - new/0,1 included, which delegates to the same engine. The
  # defoverridable accompanying the generated constructor has no counterpart here: it
  # exists so that a module can redefine what the macro injected into it, and nothing is
  # injected into this one.

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.NotIncluded
  alias Hologram.Reflection

  @resolution_key {__MODULE__, :resolution}

  defstruct __meta__: %Metadata{},
            created_at: nil,
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
          __meta__: Metadata.t(),
          created_at: DateTime.t() | nil,
          granted_by: struct | NotIncluded.t() | nil,
          granted_by_id: Entity.id() | nil,
          id: Entity.id() | nil,
          resource_id: Entity.id() | nil,
          resource_type: atom | nil,
          role: atom | module | nil,
          updated_at: DateTime.t() | nil,
          user: struct | NotIncluded.t() | nil,
          user_id: Entity.id() | nil
        }

  @doc """
  Returns the list of attribute definitions for the role grant entity type, sorted by attribute name.
  The enum value sets are computed from the compiled data model: resource_type values are the entity type table names, and role values are the union of the entity types' declared role names and the global role modules.
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
  Returns the module each policy definition of the role grant entity type was declared in, in the order of __policies__/0.
  Empty - the visibility policy of role grants is framework-supplied, not declared.
  """
  @spec __policy_sources__() :: list(module)
  def __policy_sources__, do: []

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
  Returns the role declarations of the role grant entity type as written, with the module each was declared in.
  Empty - roles are granted on resources, and role grant rows are not resources.
  """
  @spec __role_declarations__() :: list({atom, keyword, module})
  def __role_declarations__, do: []

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
  @spec entity_type(atom) :: module | nil
  # The inverse of resource_type/1, over the mapping rather than over a module sweep - a stored
  # label is a table name, and the mapping is the build's own table-name-per-entity-type. Answers
  # nil for a label naming no table, which a stored row's column cannot be but a client's write
  # can: an enum decodes to whatever atom it spells rather than to a declared value.
  def entity_type(resource_type) do
    table = Atom.to_string(resource_type)

    case Enum.find(DB.mapping(), fn {_entity_type, entry} -> entry.table == table end) do
      {entity_type, _entry} -> entity_type
      nil -> nil
    end
  end

  @doc """
  Raises - a role grant is written through grant_role/revoke_role and constructed nowhere.
  Present so that this type answers the constructor every entity type answers, with the refusal the engine already gives it.
  """
  @spec new(%{optional(atom) => any} | keyword) :: t
  def new(values \\ []), do: Entity.new(__MODULE__, values)

  @doc false
  @spec resource_type(module) :: atom
  # The atom set is bounded by the app's entity types, all named at build time - the table
  # names they derive can't be influenced at runtime.
  # sobelow_skip ["DOS.StringToAtom"]
  def resource_type(entity_type) do
    entity_type
    |> Mapper.table_name()
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> String.to_atom()
  end

  @doc false
  @spec reset_resolution_cache() :: :ok
  def reset_resolution_cache do
    :persistent_term.erase(@resolution_key)

    :ok
  end

  @doc """
  Returns the entity type designated as the app's user, or nil when none is designated.

  Read from the same cached resolution the store's own definition uses, so the answer costs
  no module sweep - unlike `Hologram.Reflection.user_entity/0`, which computes it.
  """
  @spec user_entity() :: module | nil
  def user_entity, do: resolved(:user_entity)

  defp build_resolution do
    entity_types = Enum.reject(Reflection.list_entities(), &(&1 == __MODULE__))

    resource_type_values =
      entity_types
      |> Enum.map(&resource_type/1)
      |> Enum.sort()

    entity_role_names =
      Enum.flat_map(entity_types, fn entity_type ->
        Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)
      end)

    role_values =
      entity_role_names
      |> Enum.concat(Reflection.list_roles())
      |> Enum.uniq()
      |> Enum.sort_by(&Codec.encode(&1, :enum))

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
