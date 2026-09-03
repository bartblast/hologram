defmodule Hologram.Auth.RoleGrant do
  @moduledoc false

  # The role store: one row per granted role. Grant shapes by nil pattern: an instance
  # grant names an entity type and id, a type-wide grant leaves entity_id nil, and a
  # global grant leaves both nil. A row's role is an entity role name (:admin) or a global
  # role module (MyApp.Roles.Admin).
  #
  # This module implements the entity contract by hand instead of through use
  # Hologram.Entity, because three parts of its definition are facts of the app, unknown
  # when the dep compiles: the role enum values (the app's declared role names and global
  # role modules), the
  # entity_type enum values (the app's entity type modules), and the relationship targets
  # (the app's designated user entity type). The reflection functions below compute those
  # facts when called - by then the app is compiled - so every consumer reading entity
  # definitions through the standard reflection interface sees an ordinary, fully
  # resolved definition. Keep the hand-written contract in sync with what use
  # Hologram.Entity generates - new/0,1 included, which delegates to the same engine. The
  # defoverridable accompanying the generated constructor has no counterpart here: it
  # exists so that a module can redefine what the macro injected into it, and nothing is
  # injected into this one.

  alias Hologram.DB.Codec
  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.NotIncluded
  alias Hologram.Reflection

  # Sixteen bytes drawn once, on 2026-09-02, and fixed forever after: every grant id ever derived
  # hangs off them, so changing them would rename every row in the store.
  @namespace <<0x8B, 0x2F, 0x65, 0x0D, 0xD0, 0xCF, 0x15, 0x26, 0xDF, 0xEC, 0x20, 0x9A, 0x31, 0xD9,
               0xF6, 0x6C>>

  @resolution_key {__MODULE__, :resolution}

  defstruct __meta__: %Metadata{},
            created_at: nil,
            entity_id: nil,
            entity_type: nil,
            granted_by: %NotIncluded{relationship: :granted_by},
            granted_by_id: nil,
            id: nil,
            role: nil,
            updated_at: nil,
            user: %NotIncluded{relationship: :user},
            user_id: nil

  @type t :: %__MODULE__{
          __meta__: Metadata.t(),
          created_at: DateTime.t() | nil,
          entity_id: Entity.id() | nil,
          entity_type: atom | nil,
          granted_by: struct | NotIncluded.t() | nil,
          granted_by_id: Entity.id() | nil,
          id: Entity.id() | nil,
          role: atom | module | nil,
          updated_at: DateTime.t() | nil,
          user: struct | NotIncluded.t() | nil,
          user_id: Entity.id() | nil
        }

  @doc """
  Returns the list of attribute definitions for the role grant entity type, sorted by attribute name.
  The enum value sets are computed from the compiled data model: entity_type values are the entity type modules, and role values are the union of the entity types' declared role names and the global role modules.
  """
  @spec __attributes__() :: list({atom, atom, keyword})
  def __attributes__ do
    [
      {:entity_id, :uuid, [optional: true]},
      {:entity_type, :enum, [values: resolved(:entity_type_values), optional: true]},
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
  @spec derive_id(String.t(), atom | nil, String.t() | nil, atom) :: String.t()
  # A grant's identity is the FACT it states - this user, this resource, this role - which is what
  # the store's own unique index says. So the id is a function of that fact rather than of the
  # moment it was minted: a UUIDv5 (RFC 9562 name-based, SHA-1) over the four parts under the
  # namespace below. The browser derives the same id from the same grant, so a grant made in two
  # places at once is ONE row on every tier and there is nothing to reconcile afterwards - see
  # `deriveGrantId` in `assets/js/elixir/hologram/auth.mjs`, its hand-written twin, and the parser,
  # which recomputes this from a write's columns and refuses an id that disagrees. The four
  # parameters are identity_columns/0, in that order.
  #
  # The cost, which is deliberate: these ids are not time-ordered, so this table's primary key
  # gives up the insert locality UUIDv7 buys every other table. Recorded in `02a-database.md`
  # beside the id-format lock - it is confined to the least-inserted table in an app, on the one
  # index of its four that the framework only ever point-looks-up.
  def derive_id(user_id, entity_type, entity_id, role) do
    name =
      Enum.join(
        [
          user_id,
          entity_type && Codec.encode_enum_value(entity_type),
          entity_id,
          Codec.encode_enum_value(role)
        ],
        "\n"
      )

    # A nil part joins as the empty string, and no part can contain a newline - a uuid, an enum
    # label and a module name are all spelled without one - so the four are unambiguous.
    <<time_low_and_mid::48, _version::4, time_high::12, _variant::2, rest::62, _tail::binary>> =
      :crypto.hash(:sha, @namespace <> name)

    format_id(<<time_low_and_mid::48, 5::4, time_high::12, 2::2, rest::62>>)
  end

  @doc false
  @spec entity_type(atom) :: module | nil
  # A stored label IS the entity type module, so the only question left is membership: the value
  # set is this build's entity types, and a value outside it names no type here. Answers nil for
  # such a label, which a stored row's column cannot hold but a client's write can - an enum
  # decodes to whatever atom it spells rather than to a declared value.
  def entity_type(label) do
    if label in resolved(:entity_type_values), do: label
  end

  @doc false
  @spec identity_columns() :: list(String.t())
  # The one list of what a grant IS: the columns whose values make one grant different from
  # another, in the order the store's unique index holds them. derive_id/4 takes exactly these
  # four, in this order, and the mapper's unique index is over exactly these - and they must stay
  # the same set, because the applier reads a present grant back by the id the columns derive.
  # An index wider than the derivation lets two distinct grants derive one id, and the second is
  # swallowed by the primary key; one narrower lets one fact carry two ids, and the read-back
  # after the conflict finds nothing. A column outside this list is free to add - granted_by_id
  # already is one - and a column inside it renames every row in the store.
  def identity_columns, do: ["user_id", "entity_type", "entity_id", "role"]

  @doc """
  Raises - a role grant is written through grant_role/revoke_role and constructed nowhere.
  Present so that this type answers the constructor every entity type answers, with the refusal the engine already gives it.
  """
  @spec new(%{optional(atom) => any} | keyword) :: t
  def new(values \\ []), do: Entity.new(__MODULE__, values)

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

    entity_type_values = Enum.sort_by(entity_types, &Codec.encode(&1, :enum))

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
      entity_type_values: entity_type_values,
      role_values: role_values,
      user_entity: Reflection.user_entity()
    }
  end

  # The canonical lowercase 8-4-4-4-12 spelling, which is the only one
  # `Entity.Validator.attribute_value_valid?/2` admits for a :uuid - it checks the shape and not
  # the version, so a v5 is as much an entity id as the v7 every other table carries.
  defp format_id(uuid) do
    <<part_1::binary-size(8), part_2::binary-size(4), part_3::binary-size(4),
      part_4::binary-size(4), part_5::binary-size(12)>> = Base.encode16(uuid, case: :lower)

    "#{part_1}-#{part_2}-#{part_3}-#{part_4}-#{part_5}"
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
