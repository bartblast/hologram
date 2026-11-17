defmodule Hologram.Sync.Pot do
  @moduledoc false

  # What one batch means for one client, given what it holds: which rows it is handed whole, which
  # of the rows it holds changed and how, which it may no longer hold, and which pairs it is told
  # were added or removed. Worked out from the session's part of the batch (see
  # `Hologram.Sync.Live.parts/5`) and what the session knows of its client, with no reading of its
  # own - so it can be judged without a database.
  #
  # A row is judged by what its user may read now, and what the client holds:
  #
  # | may read | held | written | told                                     |
  # |----------|------|---------|------------------------------------------|
  # | yes      | no   | either  | the whole row, which it now holds        |
  # | yes      | yes  | yes     | the written attributes                   |
  # | yes      | yes  | no      | nothing                                  |
  # | no       | yes  | either  | to drop it, which it no longer holds     |
  # | no       | no   | either  | nothing - not even that the row exists   |
  #
  # The client files a set as pairs under the row holding it: a to-many under its source, the
  # inverse of a to-many under its target. A row it is handed states its own sets whole, so the pairs
  # left to tell are the ones filed under the rows it already holds: a pair the batch added or
  # removed, the pairs naming a row it is handed - filed under a row that held none of them while
  # the row was out of its reach - and the pairs naming a row it drops, which dropping the row
  # leaves filed under the other end.
  #
  # A pair removed in a batch can name a row the client was told to drop a batch earlier. The pairs
  # read for that earlier batch are read after its effects, so they can already miss the pair - a
  # transaction committed after the batch was read is in that read - and the drop tells nothing of
  # it. So the session also keeps the ids it told the client to drop (`dropped`), until it hands
  # the row over again: a removal naming one of them is told. That is all it tells of a row the
  # client used to hold: that a pair naming it was removed, even one added after it was dropped.

  alias Hologram.Entity
  alias Hologram.Sync.Fill
  alias Hologram.Sync.Held
  alias Hologram.Sync.PackedIds

  @type news :: %{
          appeared: list(struct),
          edges: list(map),
          patched: list({struct, map}),
          unsynced: list({String.t(), module})
        }

  @type t :: %{dropped: Held.t(), held: Held.t()}

  @doc """
  Returns what the given part of a batch tells a client, given what the session knows of it, and
  what the session knows once the client is told.

  A row handed over whole carries the sets the fill sends it with (see
  `Hologram.Sync.Fill.set_names/2`, judged by the part's synced types), each holding only the rows
  the client holds once told, so no set names a row it was never given. The changes of a patched
  row are the attributes the batch wrote that the row has - an attribute a newer peer wrote, which
  this build's row lacks, is passed over.

  The rows go out in id order within each type, and the pairs as `Hologram.Sync.Frame.deltas/2`
  takes them. Any order the frame applies them in leaves the same facts behind: a pair told here is
  never one a row handed over states.

  The same part decided twice - the dispatcher reads a batch again after a crash - tells again what
  it told, changing nothing the client holds.

  Given `trust_held?: false`, every row the user may read is handed over whole, held or not, and
  none patched: for a batch that may already be in some of what the client holds and not in the
  rest, so what it holds of a row can be right while the pairs filed under other rows naming it are
  not. Handing the row over states its sets and tells those pairs.
  """
  @spec decide(t, map, keyword) :: {news, t}
  def decide(pot, part, opts \\ []) do
    synced = MapSet.new(part.synced_types)
    trust_held? = Keyword.get(opts, :trust_held?, true)

    judged = Enum.map(part.checked, &judge_type(&1, pot.held, part, trust_held?))

    appeared =
      Enum.flat_map(judged, fn {_entity_type, appeared, _patched, _unsynced} -> appeared end)

    unsynced =
      Enum.flat_map(judged, fn {entity_type, _appeared, _patched, unsynced} ->
        Enum.map(unsynced, &{&1, entity_type})
      end)

    told = tell(pot, appeared, unsynced)
    put_keys = MapSet.new(appeared, &{&1.__struct__, &1.id})

    moved =
      appeared
      |> Enum.map(&{&1.__struct__, &1.id})
      |> Enum.concat(Enum.map(unsynced, fn {id, entity_type} -> {entity_type, id} end))
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    lookup = lookup(part.pairs, Map.keys(part.pair_effects), moved)

    edges =
      part
      |> pair_effect_edges(told, put_keys, lookup)
      |> Enum.concat(arrival_edges(appeared, lookup, told.held, put_keys))
      |> Enum.concat(departure_edges(unsynced, lookup, told.held, put_keys))
      |> Enum.uniq()
      |> Enum.sort()

    patched =
      Enum.flat_map(judged, fn {_entity_type, _appeared, patched, _unsynced} -> patched end)

    news = %{
      appeared: Enum.map(appeared, &with_sets(&1, lookup, told.held, synced)),
      edges: edges,
      patched: patched,
      unsynced: unsynced
    }

    {news, told}
  end

  @doc """
  Returns what a session knows of a client once it is told to drop the given rows of the given
  entity type: they are no longer held, and are among the dropped (see the comment above) until they
  are handed over again. Also for rows the client may hold pairs naming without holding the rows -
  a set it was sent can name a row it was never given - so a removal of such a pair is told.
  """
  @spec drop(t, module, list(String.t())) :: t
  def drop(pot, entity_type, ids) do
    %{
      pot
      | dropped: Held.add(pot.dropped, entity_type, ids),
        held: Held.remove(pot.held, entity_type, ids)
    }
  end

  @doc """
  Returns what a session knows of a client holding the given ids, which it has told to drop none.
  """
  @spec from_held(Held.t()) :: t
  def from_held(held), do: %{dropped: Held.new(), held: held}

  @doc """
  Returns what a session knows of a client once it is handed the given rows of the given entity
  type: they are held, and no longer among the dropped.
  """
  @spec hand_over(t, module, list(String.t())) :: t
  def hand_over(pot, entity_type, ids) do
    %{
      pot
      | dropped: Held.remove(pot.dropped, entity_type, ids),
        held: Held.add(pot.held, entity_type, ids)
    }
  end

  @doc """
  Returns what a session knows of a client holding nothing.
  """
  @spec new() :: t
  def new, do: from_held(Held.new())

  @doc """
  Returns what a whole entity type read again for one user tells a client, given what the session
  knows of it - the rows of it the user may read now, sets included, as the fill reads them - and
  what the session knows once the client is told: the rows it doesn't hold are handed over, and
  the ones it holds that the read left out are dropped.

  The pairs filed under the rows it already holds are read with the given function, handed the
  ids of every row handed over or dropped, per entity type - the rows only this diff names (see
  `Hologram.Sync.Live.pairs_touching/2`). A handed-over row's sets keep only the rows the client
  holds once told, as `decide/3`'s do.

  What a row it holds now holds is not told: a type read again because a grant moved changed who
  may read its rows, not the rows - unless given `trust_held?: false`, as `decide/3` is, when every
  row read is handed over.
  """
  @spec reread(
          t,
          module,
          list(struct),
          (%{module => list(String.t())} -> %{{module, atom, module} => binary}),
          keyword
        ) :: {news, t}
  def reread(pot, entity_type, rows, read_pairs, opts \\ []) do
    trust_held? = Keyword.get(opts, :trust_held?, true)

    held_ids =
      pot.held
      |> Held.ids(entity_type)
      |> MapSet.new()

    read_ids = MapSet.new(rows, & &1.id)

    appeared =
      rows
      |> Enum.reject(&(trust_held? and MapSet.member?(held_ids, &1.id)))
      |> Enum.sort_by(& &1.id)

    unsynced_ids =
      held_ids
      |> MapSet.difference(read_ids)
      |> Enum.sort()

    unsynced = Enum.map(unsynced_ids, &{&1, entity_type})
    told = tell(pot, appeared, unsynced)
    put_keys = MapSet.new(appeared, &{entity_type, &1.id})

    moved = %{entity_type => Enum.map(appeared, & &1.id) ++ unsynced_ids}

    lookup =
      if appeared == [] and unsynced == [],
        do: lookup(%{}, [], %{}),
        else: lookup(read_pairs.(moved), [], moved)

    edges =
      appeared
      |> arrival_edges(lookup, told.held, put_keys)
      |> Enum.concat(departure_edges(unsynced, lookup, told.held, put_keys))
      |> Enum.uniq()
      |> Enum.sort()

    news = %{
      appeared: Enum.map(appeared, &held_sets_only(&1, told.held)),
      edges: edges,
      patched: [],
      unsynced: unsynced
    }

    {news, told}
  end

  @doc """
  Returns the rows the given part of a batch carries verdicts of that the client holds, as the
  session knew it before the batch, each with those verdicts (`{row, verdicts}`) - the rows whose
  verdicts may have moved without the row being handed over. A row the batch hands over whole is
  not among them: it travels with its verdicts.
  """
  @spec verdict_rows(t, map) :: list({struct, map})
  def verdict_rows(pot, part) do
    Enum.flat_map(part.verdicts, fn {entity_type, verdicts_by_id} ->
      readable = Map.fetch!(part.readable, entity_type)

      for {id, verdicts} <- verdicts_by_id,
          Held.member?(pot.held, entity_type, id),
          do: {Map.fetch!(readable, id), verdicts}
    end)
  end

  # The pairs filed under the rows the client holds that name a row it is handed: none was told
  # while the row was out of its reach.
  defp arrival_edges(appeared, lookup, held, put_keys) do
    Enum.flat_map(appeared, fn row ->
      row.__struct__
      |> facts_naming(row.id, lookup)
      |> Enum.filter(&told_under?(&1, held, put_keys))
      |> Enum.map(&edge(&1, :add_relationship))
    end)
  end

  # The pairs filed under the rows the client still holds that name a row it drops: dropping a row
  # takes only the pairs filed under it.
  defp departure_edges(unsynced, lookup, held, put_keys) do
    Enum.flat_map(unsynced, fn {id, entity_type} ->
      entity_type
      |> facts_naming(id, lookup)
      |> Enum.filter(&told_under?(&1, held, put_keys))
      |> Enum.map(&edge(&1, :del_relationship))
    end)
  end

  defp edge({holder_type, holder_id, relationship, _other_type, other_id}, op) do
    %{
      entity_id: holder_id,
      op: op,
      relationship: relationship,
      target_id: other_id,
      type: holder_type
    }
  end

  # The facts one pair of a to-many puts on the client, each as `{holder type, holder id,
  # relationship, other type, other id}`: the source holds the target in the to-many, and the target
  # holds the source in each inverse of it its type declares.
  defp facts({source_type, name, target_type} = key, source_id, target_id, lookup) do
    inverses =
      for inverse <- Map.fetch!(lookup.inverses, key) do
        {target_type, target_id, inverse, source_type, source_id}
      end

    [{source_type, source_id, Atom.to_string(name), target_type, target_id} | inverses]
  end

  # The facts of every pair naming the given row, filed under the pair's other end. The facts filed
  # under the row itself go with it: a row handed over states its sets, and a row dropped takes
  # them.
  defp facts_naming(entity_type, id, lookup) do
    lookup.pairs
    |> Enum.flat_map(fn {{source_type, _name, target_type} = key, packed} ->
      targets = if source_type == entity_type, do: PackedIds.rights_of(packed, id), else: []
      sources = if target_type == entity_type, do: sources_of(lookup, key, id), else: []

      Enum.flat_map(targets, &facts(key, id, &1, lookup)) ++
        Enum.flat_map(sources, &facts(key, &1, id, lookup))
    end)
    |> Enum.reject(fn {holder_type, holder_id, _relationship, _other_type, _other_id} ->
      {holder_type, holder_id} == {entity_type, id}
    end)
  end

  defp held?(held, {entity_type, id}), do: Held.member?(held, entity_type, id)

  # A set of a row handed over from a read through the read rules keeps only the rows the client
  # holds once told: a row of it the client doesn't hold is told later, when it is handed over,
  # under this row - and one never told can never be taken back out.
  defp held_sets_only(row, held) do
    sets =
      for name <- Entity.includable_names(row.__struct__),
          members = Map.fetch!(row, name),
          is_list(members),
          do: {name, Enum.filter(members, &Held.member?(held, &1.__struct__, &1.id))}

    struct(row, sets)
  end

  # How each checked row of one type is judged: the rows handed over whole, the patches, and the
  # ids dropped.
  defp judge_type({entity_type, packed_ids}, held, part, trust_held?) do
    {held_packed, _not_held} = Held.split(held, entity_type, packed_ids)

    held_ids =
      held_packed
      |> PackedIds.unpack()
      |> MapSet.new()

    readable = Map.get(part.readable, entity_type, %{})

    appeared =
      readable
      |> Enum.reject(fn {id, _row} -> trust_held? and MapSet.member?(held_ids, id) end)
      |> Enum.sort_by(fn {id, _row} -> id end)
      |> Enum.map(fn {_id, row} -> row end)

    patched = if trust_held?, do: patches(held_ids, readable, part.written), else: []

    unsynced =
      held_ids
      |> Enum.reject(&Map.has_key?(readable, &1))
      |> Enum.sort()

    {entity_type, appeared, patched, unsynced}
  end

  # What finding the facts of the given pairs needs, worked out once per call: the inverses each
  # to-many has, and the pairs whose target is a row handed over or dropped, by target - the only
  # rows looked up by target, given per entity type. A search by source is cheap on the packed
  # pairs, one by target reads them all, so those are read once and indexed.
  defp lookup(pairs, more_keys, moved) do
    keys = Enum.uniq(Map.keys(pairs) ++ more_keys)

    inverses =
      Map.new(keys, fn {source_type, name, target_type} = key ->
        names =
          target_type
          |> Entity.inverses_of_to_many(source_type, Atom.to_string(name))
          |> Enum.map(&Atom.to_string/1)

        {key, names}
      end)

    sources =
      for {{_source_type, _name, target_type} = key, packed} <- pairs,
          Map.has_key?(moved, target_type),
          into: %{},
          do: {key, PackedIds.index_lefts_by_right(packed, Map.fetch!(moved, target_type))}

    %{inverses: inverses, pairs: pairs, sources: sources}
  end

  # The pairs the batch added or removed, each told under the ends of it the client holds that are
  # not handed over whole: added when the pair is there now and the other end is held, removed when
  # it is gone and the client holds the other end or was told to drop it - every row it held before
  # is one of the two - so a removal never names a row the client never had. A to-many of whose
  # types the client holds no row is passed over without a pair of it being read.
  defp pair_effect_edges(part, told, put_keys, lookup) do
    for {{source_type, _name, target_type} = key, packed} <- part.pair_effects,
        Held.any?(told.held, source_type) or Held.any?(told.held, target_type),
        {source_id, target_id} <- PackedIds.unpack_pairs(packed),
        {_holder_type, _holder_id, _relationship, other_type, other_id} = fact <-
          facts(key, source_id, target_id, lookup),
        told_under?(fact, told.held, put_keys),
        op = pair_effect_op(lookup, key, {source_id, target_id}, told, {other_type, other_id}),
        do: edge(fact, op)
  end

  defp pair_effect_op(lookup, key, {source_id, target_id}, told, other) do
    exists? =
      lookup.pairs
      |> Map.get(key, "")
      |> PackedIds.pair_member?(source_id, target_id)

    cond do
      exists? and held?(told.held, other) -> :add_relationship
      not exists? and (held?(told.held, other) or held?(told.dropped, other)) -> :del_relationship
      true -> nil
    end
  end

  # The held rows the batch wrote that the user may still read, each with what it wrote of them.
  defp patches(held_ids, readable, written) do
    held_ids
    |> Enum.sort()
    |> Enum.flat_map(fn id ->
      with {:ok, row} <- Map.fetch(readable, id),
           {:ok, names} <- Map.fetch(written, id),
           changes when changes != %{} <- patch(row, names) do
        [{row, changes}]
      else
        _nothing_to_patch -> []
      end
    end)
  end

  # Names arrive as the log spells them rather than as atoms, so they are matched against the row's
  # own fields - which never invents an atom for something this node has never compiled.
  defp patch(row, names) do
    row
    |> Map.from_struct()
    |> Map.filter(fn {field, _value} -> Atom.to_string(field) in names end)
  end

  # The type of the rows the given set of a row holds, and their ids as the pairs name them.
  defp set(entity_type, name, id, lookup) do
    case Entity.inverse_relationship(entity_type, name) do
      %{forward: forward, target: source_type} ->
        {source_type, sources_of(lookup, {source_type, forward, entity_type}, id)}

      nil ->
        [target_type] = Entity.relationship_target(entity_type, name)
        packed = Map.get(lookup.pairs, {entity_type, name, target_type}, "")

        {target_type, PackedIds.rights_of(packed, id)}
    end
  end

  # The sources of the pairs of the given to-many whose target is the given row - one handed over or
  # dropped, the only rows looked up by target (see `lookup/3`). A to-many with no pair has no
  # index; one with pairs always has one when a row of its target type moved, so a missing index
  # raises. The index holds only the moved rows, so a row of that type that didn't move has no
  # sources here.
  defp sources_of(lookup, key, target_id) do
    case {Map.fetch(lookup.sources, key), Map.has_key?(lookup.pairs, key)} do
      {{:ok, index}, _has_pairs?} -> PackedIds.lefts_in(index, target_id)
      {:error, false} -> []
    end
  end

  # What the client is told moves the session's knowledge of it: a row handed over is held and no
  # longer dropped, and a row dropped is no longer held, and is kept among the dropped.
  defp tell(pot, appeared, unsynced) do
    handed_over =
      appeared
      |> Enum.group_by(& &1.__struct__, & &1.id)
      |> Enum.reduce(pot, fn {entity_type, ids}, acc -> hand_over(acc, entity_type, ids) end)

    unsynced
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.reduce(handed_over, fn {entity_type, ids}, acc -> drop(acc, entity_type, ids) end)
  end

  # A fact goes to the client under a holder it holds once told, unless the holder is handed over
  # whole, which states the set itself.
  defp told_under?(
         {holder_type, holder_id, _relationship, _other_type, _other_id},
         held,
         put_keys
       ) do
    held?(held, {holder_type, holder_id}) and
      not MapSet.member?(put_keys, {holder_type, holder_id})
  end

  # A row handed over whole states its sets: each holds the rows the pairs name that the client holds
  # once told, as rows bearing only their ids - all a set is sent as (see
  # `Hologram.Sync.WireData.row/1`).
  defp with_sets(row, lookup, held, synced) do
    entity_type = row.__struct__

    sets =
      for name <- Fill.set_names(entity_type, synced) do
        {other_type, other_ids} = set(entity_type, name, row.id, lookup)

        members =
          for other_id <- other_ids,
              Held.member?(held, other_type, other_id),
              do: struct(other_type, id: other_id)

        {name, members}
      end

    struct(row, sets)
  end
end
