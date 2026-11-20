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
  # name at the tab's point, or a marker saying it is new since (see `new_since/0`). A name the
  # walk never touched is absent and means itself, so a chain renaming one attribute costs one
  # entry, whatever the size of the model. The model term at the tab's point answers the two things
  # the ops can't: whether an attribute turned server-only off was server-only for the tab, and
  # which entity type the tab took as its user.

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Migration.Loader

  # `model_hash` is the hash of the running model the lens translates from, set by `for_hash/1`
  # for whoever starts a session with it to check that model still runs.
  defstruct global_roles: %{}, model_hash: nil, resolved: nil, types: %{}

  @type old(name) :: name | :"$new"

  @type t :: %__MODULE__{
          global_roles: %{module => old(module)},
          model_hash: String.t() | nil,
          resolved: resolved | nil,
          types: %{module => type_entry}
        }

  # What the lens answers for a name new since. An atom no declared name can be: attribute and
  # relationship names can't hold a `$`, enum values and entity role names begin with a lowercase
  # letter or an underscore unless they are modules, and entity types and global roles are
  # modules.
  @new :"$new"

  @type history :: %{
          migrations: list(%{atom => any}),
          model_hash: String.t(),
          positions: %{String.t() => list(String.t())},
          recorded: %{String.t() => String.t()}
        }

  # The lens in what a frame spells: labels, wire keys and encoded enum values (see `resolve/2`).
  @type resolved :: %{
          by_label: %{String.t() => module},
          by_old_label: %{String.t() => module},
          entity_types: MapSet.t(module),
          grant_global_roles: %{String.t() => old(String.t())},
          grant_roles: %{String.t() => %{String.t() => old(String.t())}},
          grant_types: %{String.t() => old(String.t())},
          wire: %{module => wire_entry}
        }

  @type wire_entry :: %{
          edges: %{String.t() => old(String.t())},
          enums: %{atom => %{String.t() => old(String.t())}},
          keys: %{atom => old(atom)},
          label: old(String.t())
        }

  @grant_label Codec.encode_enum_value(RoleGrant)

  # How long a process waiting for another to work out a history or a lens sleeps between looks.
  @wait_ms 5

  # How long an answer not kept is shared with whoever asks for it.
  @shared_ms 1_000

  # How often a waiting process asks for the lock again.
  @lock_ms 100

  # What a frame spells of a type the lens changes nothing of, bar its label.
  @untouched_wire %{edges: %{}, enums: %{}, keys: %{}, label: nil}

  # A type entry mapping no name of the type to another.
  @untouched_entry %{attributes: %{}, enums: %{}, old: nil, relationships: %{}, roles: %{}}

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
  Returns the lens a tab built against the data model of the given hash is served through,
  resolved for the current model's entity types, or `:error` when it can't be served through one:
  the hash names no point of the release's migration history, or a change since it can't be given
  back by renaming (see `build/2`).

  A hash standing for several points is served from the latest when they all agree (see
  `for_hash/3`). Once a history leading to the running model is read, it is kept for that model,
  and each point's lens is built once and kept under a key of its own, so a lens a session holds is
  never replaced under it. Each is worked out by one process at a time, so a wave of old tabs
  reconnecting after a deploy reads the table and builds a point's lens once, and a hash naming no
  point then costs one map lookup. A history leading elsewhere is not kept, nor is a read the
  database fails, which raises.
  """
  @spec for_hash(String.t()) :: {:ok, t} | :error
  def for_hash(model_hash) do
    current_hash = Model.hash()
    entity_types = Model.entity_types()

    with {:ok, history} <- cached_history(current_hash),
         {:ok, versions} <- positions(history, model_hash) do
      agreed(versions, &cached_lens(current_hash, &1, history, entity_types))
    end
  end

  @doc """
  Returns the history `for_hash/3` reads, from every version the migration table records with its
  model hash and the release's migrations as `Hologram.Migration.Loader.list!/0` gives them.

  Each version stands for the hash the table records for it, and for the hash this Hologram works
  out for the model its file leaves: a deploy of a Hologram whose model term differs from the one
  that applied a file builds bundles under a hash the table never recorded. Only the running
  Hologram's is worked out, so a bundle of a release in between whose Hologram spelled the term
  another way still can't be placed. A hash can stand for several versions - a rename and back, or
  two attributes swapping names - each listed, the latest first.

  The history also holds the hash of the model all the files fold to, which is the running model's
  when the release is consistent.
  """
  @spec history(%{String.t() => String.t()}, list(%{atom => any})) :: history
  def history(recorded, migrations) do
    {model, computed} =
      Enum.reduce(migrations, {Model.empty(), []}, fn migration, {model, acc} ->
        folded = Model.fold(model, migration.ops)

        {folded, [{migration.version, Model.hash(folded)} | acc]}
      end)

    positions =
      recorded
      |> Enum.concat(computed)
      |> Enum.group_by(fn {_version, model_hash} -> model_hash end, fn {version, _hash} ->
        version
      end)
      |> Map.new(fn {model_hash, versions} ->
        latest_first =
          versions
          |> Enum.uniq()
          |> Enum.sort(:desc)

        {model_hash, latest_first}
      end)

    %{
      migrations: migrations,
      model_hash: Model.hash(model),
      positions: positions,
      recorded: recorded
    }
  end

  @doc """
  Returns what `for_hash/1` answers for the given hash, given the history (see `history/2`) and the
  current model's entity types.

  A recorded point the release has no migration for can't be served from, and neither can one
  before a recorded version the release lacks, since its ops are what the lens is built from.

  A hash standing for several points is served only when every one of them is servable and gives
  the same translation, from the latest. A tab says only its hash, and the points can mean
  different things by the same names: two attributes swapped through a temporary name leave a
  model of the same hash whose values sit under each other's names. A rename and back translates
  as nothing did. A tab greeting with the running model's own hash is never asked about here, and
  is served as current even when an earlier point shares that hash.
  """
  @spec for_hash(String.t(), history, list(module)) :: {:ok, t} | :error
  def for_hash(model_hash, history, entity_types) do
    with {:ok, versions} <- positions(history, model_hash) do
      agreed(versions, &lens_at(&1, history, entity_types))
    end
  end

  @doc """
  Drops what `for_hash/1` keeps, for tests that change the migration table.
  """
  @spec reset_cache() :: :ok
  def reset_cache do
    for {key, _value} <- :persistent_term.get(),
        is_tuple(key) and tuple_size(key) > 1 and elem(key, 0) == __MODULE__ do
      :persistent_term.erase(key)
    end

    :ok
  end

  @doc """
  Returns the current entity type of the given type label as the tab spells it - a type it names
  by its name at its point of the history - or nil for a label naming no type of the current model.
  Asked of a resolved lens (see `resolve/2`).
  """
  @spec current_type(t, String.t()) :: module | nil
  def current_type(%__MODULE__{resolved: resolved} = lens, old_label) do
    case Map.fetch(resolved.by_old_label, old_label) do
      {:ok, entity_type} ->
        entity_type

      :error ->
        entity_type = existing_module(old_label)

        # A current type under a name the walk touched was renamed to it, or created under it:
        # the tab's type of that name is another, or none.
        if MapSet.member?(resolved.entity_types, entity_type) and
             not Map.has_key?(lens.types, entity_type),
           do: entity_type
    end
  end

  @doc """
  Returns the given message of a sync session to its client - deltas or a completeness marker -
  translated into the tab's names, and any other message as it is (see `resolve/2`).

  Every delta's type takes its old label, and a delta of a type new since is dropped. A row's data
  and revisions take the old keys, without the keys of what is new since, and its enum values
  their old labels. A patch left with nothing to say is dropped, and so is an edge of a
  relationship new since. Verdicts pass as they are: a verdict is keyed by a digest of its
  condition, so one whose condition the tab's rules spell the same way keeps its key and meaning,
  and one they spell otherwise is a key the tab never asks for.

  A grant's entity type and role take their old labels too: an entity role is named per entity
  type, a global role by its module when the grant names no entity type.

  A row the tab can't be told about (see `servable?/2`) is to be kept from it before this: one
  reaching here goes as a dropped delta rather than with a label the tab doesn't know.
  """
  @spec message(t, tuple) :: tuple
  def message(lens, {:sync_deltas, cursor, deltas, claim}) do
    {:sync_deltas, cursor, Enum.flat_map(deltas, &delta(lens, &1)), claim}
  end

  def message(lens, {:sync_synced, {:types, types}, cursor}) do
    old_types =
      types
      |> Enum.map(&old_type(lens, &1))
      |> Enum.reject(&(&1 == @new))

    {:sync_synced, {:types, old_types}, cursor}
  end

  def message(_lens, message), do: message

  @doc """
  Returns the given lens with what a frame spells worked out for it, from the given entity types
  of the current model: each type's old label, the wire keys of its attributes and relationships -
  a to-one's reference field, a to-many's set - with their old names, and the old labels of its
  enum values. An inverse of a to-many whose relationship is new since is a set the tab never had.
  Other inverses keep their names: they are declared in code, not in the model, so the history
  says nothing of them. An inverse of a to-one never travels, its rows' reference fields saying
  what it holds.
  """
  @spec resolve(t, list(module)) :: t
  def resolve(lens, entity_types) do
    current_types = MapSet.new(entity_types)

    # A type new since is dropped whatever its module declares, listed or not.
    new_types =
      for {entity_type, %{old: @new}} <- lens.types,
          into: %{},
          do: {entity_type, %{@untouched_wire | label: @new}}

    wire =
      entity_types
      |> Enum.map(&{&1, wire_entry(lens, &1)})
      |> Enum.reject(fn {entity_type, entry} -> untouched?(lens, entity_type, entry) end)
      |> Map.new()
      |> Map.merge(new_types)

    # A renamed type the current model lists, so the two ways `current_type/2` answers agree.
    by_old_label =
      for {entity_type, %{old: old}} <- lens.types,
          old != @new,
          MapSet.member?(current_types, entity_type),
          into: %{},
          do: {label(old), entity_type}

    resolved = %{
      by_label: Map.new(wire, fn {entity_type, _entry} -> {label(entity_type), entity_type} end),
      by_old_label: by_old_label,
      entity_types: current_types,
      grant_global_roles:
        Map.new(lens.global_roles, fn {role, old} -> {label(role), old_label(old)} end),
      grant_roles:
        Map.new(lens.types, fn {entity_type, entry} ->
          {label(entity_type),
           Map.new(entry.roles, fn {role, old} -> {label(role), old_label(old)} end)}
        end),
      grant_types:
        Map.new(lens.types, fn {entity_type, entry} ->
          {label(entity_type), old_label(entry.old)}
        end),
      wire: wire
    }

    %{lens | resolved: resolved}
  end

  @doc """
  Returns the given row with the rows of its to-many sets the tab can't be told about left out
  (see `servable?/2`), so no set it is sent names a row it is kept from.
  """
  @spec servable_members(t, struct) :: struct
  def servable_members(lens, %entity_type{} = row) do
    to_many = for {name, [_target], _opts} <- entity_type.__relationships__(), do: name
    inverses = for {name, _type, _opts} <- entity_type.__inverse_relationships__(), do: name

    Enum.reduce(to_many ++ inverses, row, fn name, acc ->
      case Map.get(acc, name) do
        members when is_list(members) ->
          Map.put(acc, name, Enum.filter(members, &servable?(lens, &1)))

        _not_a_set ->
          acc
      end
    end)
  end

  @doc """
  Returns whether the tab can be told about the given row: not when it holds an enum value new
  since, which the tab's code has no label for, nor for a role grant naming an entity type or a
  role new since.
  """
  @spec servable?(t, struct) :: boolean
  def servable?(lens, %RoleGrant{entity_type: nil, role: role}) do
    old_global_role(lens, role) != @new
  end

  def servable?(lens, %RoleGrant{entity_type: entity_type, role: role}) do
    old_type(lens, entity_type) != @new and old_role(lens, entity_type, role) != @new
  end

  def servable?(lens, %entity_type{} = row) do
    lens
    |> sent_enums(entity_type)
    |> Enum.all?(fn {attribute, values} ->
      value = Map.get(row, attribute)

      is_nil(value) or not is_atom(value) or Map.get(values, value, value) != @new
    end)
  end

  @doc """
  Returns whether the tab can be kept from some row of the given entity type (see `servable?/2`) -
  which a caller holding only ids has to read rows to find out.
  """
  @spec withholds?(t, module) :: boolean
  def withholds?(lens, RoleGrant) do
    Enum.any?(lens.global_roles, fn {_role, old} -> old == @new end) or
      Enum.any?(lens.types, fn {_entity_type, entry} ->
        entry.old == @new or Enum.any?(entry.roles, fn {_role, old} -> old == @new end)
      end)
  end

  def withholds?(lens, entity_type) do
    lens
    |> sent_enums(entity_type)
    |> Enum.any?(fn {_attribute, values} ->
      Enum.any?(values, fn {_value, old} -> old == @new end)
    end)
  end

  @doc """
  Returns what the lens answers for a name new since, which the tab's model doesn't have.
  """
  @spec new_since() :: :"$new"
  def new_since, do: @new

  @doc """
  Returns what the tab calls the given attribute of the given entity type, or the new-since
  marker (see `new_since/0`).
  """
  @spec old_attribute(t, module, atom) :: old(atom)
  def old_attribute(lens, entity_type, name), do: old_member(lens, entity_type, :attributes, name)

  @doc """
  Returns what the tab calls the given value of the given enum attribute of the given entity type,
  or the new-since marker - for a value added since, or a value of an attribute or a type added
  since.
  """
  @spec old_enum_value(t, module, atom, atom) :: old(atom)
  def old_enum_value(lens, entity_type, attribute, value) do
    case old_attribute(lens, entity_type, attribute) do
      @new ->
        @new

      _old_attribute ->
        values = Map.get(type_entry(lens, entity_type).enums, attribute, %{})

        Map.get(values, value, value)
    end
  end

  @doc """
  Returns what the tab calls the given global role module, or the new-since marker.
  """
  @spec old_global_role(t, module) :: old(module)
  def old_global_role(lens, role), do: Map.get(lens.global_roles, role, role)

  @doc """
  Returns what the tab calls the given relationship of the given entity type, or the new-since
  marker.
  """
  @spec old_relationship(t, module, atom) :: old(atom)
  def old_relationship(lens, entity_type, name) do
    old_member(lens, entity_type, :relationships, name)
  end

  @doc """
  Returns what the tab calls the given role of the given entity type, or the new-since marker.
  """
  @spec old_role(t, module, atom) :: old(atom)
  def old_role(lens, entity_type, name), do: old_member(lens, entity_type, :roles, name)

  @doc """
  Returns what the tab calls the given entity type, or the new-since marker.
  """
  @spec old_type(t, module) :: old(module)
  def old_type(lens, entity_type), do: type_entry(lens, entity_type).old

  defp delta(lens, %{type: label} = delta) do
    wire = wire_for(lens, label)

    cond do
      wire.label == @new ->
        []

      label == @grant_label and delta.op in [:put_entity, :patch_entity] ->
        translate_grant(lens, delta)

      Map.has_key?(delta, :data) ->
        translate_data(%{delta | type: wire.label}, wire)

      true ->
        [%{delta | type: wire.label}]
    end
  end

  defp existing_module(label) do
    String.to_existing_atom("Elixir." <> label)
  rescue
    ArgumentError -> nil
  end

  defp grant_role(resolved, nil, role), do: Map.get(resolved.grant_global_roles, role, role)

  defp grant_role(resolved, type_label, role) do
    resolved.grant_roles
    |> Map.get(type_label, %{})
    |> Map.get(role, role)
  end

  defp label(module), do: Codec.encode_enum_value(module)

  defp old_label(@new), do: @new

  defp old_label(name), do: label(name)

  defp old_value(wire, key, value) do
    case wire.enums do
      %{^key => values} when is_binary(value) -> Map.get(values, value, value)
      _not_an_enum -> value
    end
  end

  defp translate_data(%{op: op, data: data} = delta, wire)
       when op in [:add_relationship, :del_relationship] do
    case Map.get(wire.edges, data.relationship, data.relationship) do
      @new -> []
      old -> [%{delta | data: %{data | relationship: old}}]
    end
  end

  defp translate_data(%{op: op} = delta, _wire)
       when op in [:keep_hashed, :unsync_hashed] do
    [delta]
  end

  defp translate_data(%{op: op, data: data} = delta, wire) do
    translated =
      Enum.reduce_while(data, %{}, fn {key, value}, acc ->
        case translate_field(wire, key, value) do
          @new -> {:halt, :unservable}
          :dropped -> {:cont, acc}
          {old_key, old_value} -> {:cont, Map.put(acc, old_key, old_value)}
        end
      end)

    cond do
      translated == :unservable -> []
      op == :patch_entity and says_nothing?(translated) -> []
      true -> [%{delta | data: translated}]
    end
  end

  # A grant's values name what the model declares: its entity type and its role, which is the
  # entity type's own or, on a grant naming none, a global role. Its own attributes are the
  # framework's and never change.
  defp translate_grant(lens, %{data: data} = delta) do
    resolved = lens.resolved
    type_label = Map.get(data, :entity_type)
    old_type = if type_label, do: Map.get(resolved.grant_types, type_label, type_label)
    old_role = if Map.has_key?(data, :role), do: grant_role(resolved, type_label, data.role)

    if old_type == @new or old_role == @new do
      []
    else
      old_data =
        data
        |> replace_present(:entity_type, old_type)
        |> replace_present(:role, old_role)

      [%{delta | data: old_data}]
    end
  end

  defp replace_present(data, key, value) do
    if Map.has_key?(data, key), do: Map.put(data, key, value), else: data
  end

  defp translate_field(wire, :"$revisions", revisions) do
    old_revisions =
      for {key, revision} <- revisions,
          old_key = Map.get(wire.keys, key, key),
          old_key != @new,
          into: %{},
          do: {old_key, revision}

    {:"$revisions", old_revisions}
  end

  defp translate_field(_wire, :"$verdicts", verdicts), do: {:"$verdicts", verdicts}

  defp translate_field(wire, key, value) do
    case {Map.get(wire.keys, key, key), old_value(wire, key, value)} do
      {@new, _value} -> :dropped
      {_old_key, @new} -> @new
      {old_key, old_value} -> {old_key, old_value}
    end
  end

  defp says_nothing?(data) do
    Enum.all?(data, fn
      {:"$revisions", revisions} -> revisions == %{}
      _value -> false
    end)
  end

  defp untouched?(lens, entity_type, entry) do
    not Map.has_key?(lens.types, entity_type) and entry.keys == %{} and entry.edges == %{}
  end

  defp wire_for(lens, label) do
    case Map.fetch(lens.resolved.by_label, label) do
      {:ok, entity_type} -> Map.fetch!(lens.resolved.wire, entity_type)
      :error -> %{@untouched_wire | label: label}
    end
  end

  defp wire_entry(lens, entity_type) do
    entry = type_entry(lens, entity_type)

    attribute_keys = Map.new(entry.attributes)

    {relationship_keys, edges} =
      Enum.reduce(entity_type.__relationships__(), {%{}, %{}}, fn {name, type, _opts},
                                                                  {keys, edges} ->
        case {old_relationship(lens, entity_type, name), is_list(type)} do
          {^name, _to_many?} ->
            {keys, edges}

          {@new, false} ->
            {Map.put(keys, reference_key(name), @new), edges}

          {old, false} ->
            {Map.put(keys, reference_key(name), reference_key(old)), edges}

          {old, true} ->
            {Map.put(keys, name, old), Map.put(edges, edge_name(name), edge_name(old))}
        end
      end)

    new_inverses =
      for {name, _type, _opts} <- entity_type.__inverse_relationships__(),
          inverse = Entity.inverse_relationship(entity_type, name),
          not inverse.reference?,
          old_relationship(lens, inverse.target, inverse.forward) == @new,
          do: name

    enums =
      Map.new(entry.enums, fn {attribute, values} ->
        {attribute, Map.new(values, fn {value, old} -> {label(value), old_label(old)} end)}
      end)

    %{
      edges: Map.merge(edges, Map.new(new_inverses, &{edge_name(&1), @new})),
      enums: enums,
      keys:
        attribute_keys
        |> Map.merge(relationship_keys)
        |> Map.merge(Map.new(new_inverses, &{&1, @new})),
      label: old_label(entry.old)
    }
  end

  # An edge names its relationship as a string (see `Hologram.Sync.Pot`).
  defp edge_name(@new), do: @new

  defp edge_name(name), do: Atom.to_string(name)

  # The names come from the release's own migrations, so the atoms this makes are bounded by the
  # history. A tab's old reference field may name no field any current struct has.
  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp reference_key(name), do: :"#{name}_id"

  # A history whose files fold to another model than the running one - a dev node between a model
  # edit and the migration generated for it - places a tab at a point it may not hold, so it serves
  # none. Not kept: the files can change while the model hash stays.
  defp cached_history(current_hash) do
    cached({__MODULE__, :history, current_hash}, current_hash, fn ->
      case read_history() do
        {:ok, %{model_hash: ^current_hash} = history} -> {:keep, {:ok, history}}
        {:ok, _other_model} -> {:pass, :error}
        :error -> {:pass, :error}
      end
    end)
  end

  # Each point's lens, or that it can't be served, under a key of its own: one per version, and
  # never written again for the same current model.
  defp cached_lens(current_hash, version, history, entity_types) do
    cached({__MODULE__, :lens, current_hash, version}, current_hash, fn ->
      case lens_at(version, history, entity_types) do
        {:ok, lens} -> {:keep, {:ok, %{lens | model_hash: current_hash}}}
        :error -> {:keep, :error}
      end
    end)
  end

  # Worked out by one process at a time: the others look again every few milliseconds, so a wave of
  # old tabs reconnecting after a deploy reads the table once and finds the answer as soon as it is
  # kept. Kept only while the model is the one it was worked out for: a live reload compiling
  # between the two reads would otherwise keep a lens of one model under another's hash.
  #
  # An answer not kept for good - and a raise, a read the database failed - is shared for a moment
  # with every caller, waiting or arriving, so a wave doesn't work it out again one process after
  # another. Except one worked out across a model change, which is of a model no longer running. A
  # tab whose stream a failed read ended greets again within that moment and is answered the same.
  # Waiting processes look at the answer every few milliseconds and ask for the lock less often,
  # since every ask is a call to the node's lock server.
  defp cached(key, current_hash, compute) do
    case fresh(key) do
      nil -> compute_or_wait(key, current_hash, compute)
      {:recent, outcome} -> replay(outcome)
      answer -> answer
    end
  end

  defp fresh(key) do
    case :persistent_term.get(key, nil) do
      {:recent, until, outcome} ->
        if System.monotonic_time(:millisecond) < until, do: {:recent, outcome}

      kept ->
        kept
    end
  end

  defp replay({:value, answer}), do: answer

  defp replay({:raise, kind, reason, stacktrace}), do: :erlang.raise(kind, reason, stacktrace)

  defp share(key, outcome) do
    until = System.monotonic_time(:millisecond) + @shared_ms

    :persistent_term.put(key, {:recent, until, outcome})
  end

  defp compute_or_wait(key, current_hash, compute) do
    lock = {key, self()}

    if :global.set_lock(lock, [node()], 0) do
      try do
        compute_once(key, current_hash, compute)
      after
        :global.del_lock(lock, [node()])
      end
    else
      wait(key, current_hash, compute, div(@lock_ms, @wait_ms))
    end
  end

  # A holder that dies keeps nothing, so a waiter asks for the lock again now and then.
  defp wait(key, current_hash, compute, 0), do: cached(key, current_hash, compute)

  defp wait(key, current_hash, compute, looks_left) do
    Process.sleep(@wait_ms)

    case fresh(key) do
      nil -> wait(key, current_hash, compute, looks_left - 1)
      {:recent, outcome} -> replay(outcome)
      answer -> answer
    end
  end

  defp compute_once(key, current_hash, compute) do
    case fresh(key) do
      nil -> kept(compute_outcome(compute), key, current_hash)
      {:recent, outcome} -> replay(outcome)
      answer -> answer
    end
  end

  # A hold is never shared: a caller arriving after the model is released has to read it again.
  defp compute_outcome(compute) do
    {:value, compute.()}
  rescue
    error in Hologram.StaleModelError -> reraise error, __STACKTRACE__
  catch
    kind, reason -> {:raise, kind, reason, __STACKTRACE__}
  end

  # An answer worked out across a model change is neither kept nor shared: it is of a model that no
  # longer runs, and the start of the session it was asked for checks the model again and starts
  # over (see `Hologram.Realtime.SSE.read_sync_start/6`).
  defp kept({:value, {:keep, answer}}, key, current_hash) do
    if Model.hash() == current_hash, do: keep(key, current_hash, answer)

    answer
  end

  defp kept({:value, {:pass, answer}}, key, _current_hash) do
    share(key, {:value, answer})

    answer
  end

  defp kept({:raise, kind, reason, stacktrace} = outcome, key, _current_hash) do
    share(key, outcome)

    :erlang.raise(kind, reason, stacktrace)
  end

  # One current model's history and lenses at a time: a dev node's model changes with every edit,
  # and the ones kept for the models before are never asked for again.
  defp keep({__MODULE__, :history, _current_hash} = key, current_hash, answer) do
    for {{__MODULE__, _kind, kept_hash} = kept_key, _value} <- :persistent_term.get(),
        kept_hash != current_hash do
      :persistent_term.erase(kept_key)
    end

    for {{__MODULE__, :lens, kept_hash, _version} = kept_key, _value} <- :persistent_term.get(),
        kept_hash != current_hash do
      :persistent_term.erase(kept_key)
    end

    :persistent_term.put(key, answer)
  end

  defp keep(key, _current_hash, answer), do: :persistent_term.put(key, answer)

  defp lens_at(version, history, entity_types) do
    versions = MapSet.new(history.migrations, & &1.version)
    later_recorded = for {recorded, _hash} <- history.recorded, recorded > version, do: recorded

    if MapSet.member?(versions, version) and
         Enum.all?(later_recorded, &MapSet.member?(versions, &1)) do
      {through, later} = Enum.split_with(history.migrations, &(&1.version <= version))

      with {:ok, old_model} <- fold_through(through),
           {:ok, lens} <- build(old_model, Enum.flat_map(later, & &1.ops)) do
        {:ok, resolve(lens, entity_types)}
      else
        _unservable -> :error
      end
    else
      :error
    end
  end

  defp fold_through(migrations) do
    {:ok, Enum.reduce(migrations, Model.empty(), &Model.fold(&2, &1.ops))}
  rescue
    Hologram.CompileError -> :error
  end

  defp positions(history, model_hash) do
    Map.fetch(history.positions, model_hash)
  end

  # The lens of the latest of the points a hash stands for, when every one of them gives the same
  # translation (see `for_hash/3`).
  # Built latest first, stopping at the first point that disagrees, or can't be served from.
  defp agreed([latest], lens_at), do: lens_at.(latest)

  defp agreed([latest | earlier], lens_at) do
    with {:ok, lens} <- lens_at.(latest) do
      translation = translation(lens)

      if Enum.all?(earlier, &agrees?(lens_at.(&1), translation)),
        do: {:ok, lens},
        else: :error
    end
  end

  defp agrees?({:ok, lens}, translation), do: translation(lens) == translation

  defp agrees?(:error, _translation), do: false

  # What a lens does to the names it maps, without the names it leaves as they are: a walk through
  # a rename and back records the name as its own old one, which a walk that never touched it
  # leaves out, and both translate it alike.
  defp translation(lens) do
    types =
      for {entity_type, entry} <- lens.types,
          entry = changed_entry(entity_type, entry),
          into: %{},
          do: {entity_type, entry}

    {types, changed(lens.global_roles)}
  end

  defp changed_entry(entity_type, entry) do
    enums =
      for {attribute, values} <- entry.enums,
          changed = changed(values),
          changed != %{},
          into: %{},
          do: {attribute, changed}

    changed = %{
      attributes: changed(entry.attributes),
      enums: enums,
      old: entry.old,
      relationships: changed(entry.relationships),
      roles: changed(entry.roles)
    }

    if changed == %{@untouched_entry | old: entity_type}, do: nil, else: changed
  end

  defp changed(names), do: Map.reject(names, fn {name, old} -> name == old end)

  defp read_history do
    statement = ~s(SELECT "version", "model_hash" FROM "#{Mapper.system_schema()}"."migration")

    # A read the database fails raises, as every other read starting a stream does: the stream
    # ends and the browser greets again, where an answer of `:error` would tell it never to expect
    # sync from this page.
    case Connection.query(statement) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        recorded = Map.new(rows, fn [version, model_hash] -> {version, model_hash} end)

        {:ok, history(recorded, Loader.list!())}

      {:error, error} ->
        raise error
    end
  rescue
    # A dev build's files can hold a draft no fold takes (see `Hologram.Entity.Model.fold/3`), and
    # an old tab is then told to reload rather than taking the stream down with it.
    Hologram.CompileError -> :error
  end

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
    put_type(lens, entity_type, %{new_entry(entity_type) | old: @new})
  end

  defp apply_op(%{op: :rename_entity, from: from, to: to}, lens, _old_model) do
    entry = type_entry(lens, from)
    types = Map.delete(lens.types, from)

    %{lens | types: Map.put(types, to, entry)}
  end

  defp apply_op(%{op: :add_attribute, entity: entity_type, name: name}, lens, _old_model) do
    put_member(lens, entity_type, :attributes, name, @new)
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
    put_member(lens, entity_type, :relationships, name, @new)
  end

  defp apply_op(
         %{op: :rename_relationship, entity: entity_type, from: from, to: to},
         lens,
         _old_model
       ) do
    update_type(lens, entity_type, &rename_in(&1, :relationships, from, to))
  end

  defp apply_op(%{op: :add_enum_value} = op, lens, _old_model) do
    update_enum(lens, op.entity, op.attribute, &Map.put(&1, op.value, @new))
  end

  defp apply_op(%{op: :rename_enum_value} = op, lens, _old_model) do
    update_enum(lens, op.entity, op.attribute, fn values ->
      {old, values} = Map.pop(values, op.from, op.from)

      Map.put(values, op.to, old)
    end)
  end

  defp apply_op(%{op: :add_role, entity: entity_type, name: name}, lens, _old_model) do
    put_member(lens, entity_type, :roles, name, @new)
  end

  defp apply_op(%{op: :add_role, role: role}, lens, _old_model) do
    %{lens | global_roles: Map.put(lens.global_roles, role, @new)}
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
      @new -> put_member(lens, entity_type, :attributes, name, @new)
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
    if server_only?, do: @new, else: :kept
  end

  defp attribute_change(_change, _server_only?), do: :unservable

  defp new_entry(entity_type) do
    %{attributes: %{}, enums: %{}, old: entity_type, relationships: %{}, roles: %{}}
  end

  defp old_member(lens, entity_type, kind, name) do
    entry = type_entry(lens, entity_type)
    members = Map.fetch!(entry, kind)

    if entry.old == @new, do: @new, else: Map.get(members, name, name)
  end

  # The enum attributes of the given type the walk changed values of, that the tab is sent: an
  # attribute new since is left out of what it is sent, and a server-only one is never sent, so
  # their values can't keep a row from it. A type new since is never served.
  defp sent_enums(lens, entity_type) do
    entry = type_entry(lens, entity_type)

    if entry.old == @new or entry.enums == %{} do
      []
    else
      server_only = Entity.server_only_attribute_names(entity_type)

      Enum.reject(entry.enums, fn {attribute, _values} ->
        Map.get(entry.attributes, attribute) == @new or attribute in server_only
      end)
    end
  end

  # An attribute the tab had can only have become server-only since through a change the walk
  # refuses, so it is server-only for the tab exactly when the tab's model term says so.
  defp server_only_for_tab?(lens, old_model, entity_type, name) do
    with old_type when old_type != @new <- old_type(lens, entity_type),
         old_name when old_name != @new <- old_attribute(lens, entity_type, name),
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
      @new in answers -> @new
      true -> :kept
    end
  end
end
