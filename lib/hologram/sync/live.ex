defmodule Hologram.Sync.Live do
  @moduledoc false

  # What the dispatcher hands each batch of changes it reads: which rows the batch may have changed
  # for anyone - the rows it wrote, both ends of every pair it added or removed, and the rows whose
  # read access or verdicts it moved without writing them (see `Hologram.Sync.Search`) - and who of
  # the users with a sync session on this node may read each of them now (see
  # `Hologram.Sync.Recheck`). Asked once per batch for every user at once, whatever the number of
  # sessions, and handed to each session as the part that is its user's.
  #
  # What a session makes of its part - which rows its client is sent, changed or told to drop - is
  # the session's, since only it knows what its client holds.

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.QueryCache
  alias Hologram.Policy
  alias Hologram.Policy.Edges
  alias Hologram.Sync.Fanout
  alias Hologram.Sync.PackedIds
  alias Hologram.Sync.Recheck
  alias Hologram.Sync.Search
  alias Hologram.Sync.Sessions

  @entity_ops [:del_entity, :patch_entity, :put_entity]

  @pair_ops [:add_relationship, :del_relationship]

  @written_ops [:patch_entity, :put_entity]

  # The most rows of one type one recheck statement asks about. A batch has no bound of its own - a
  # bulk write, or one change reaching many rows - and the statement can test every id it is given
  # against every user, so past this the type is asked about in several. Policy, not a derived
  # figure: it trades statements per batch against the time one statement takes before the driver
  # gives up on it.
  @recheck_chunk_size 5_000

  @type part :: %{
          checked: %{module => binary},
          own_seqs: %{String.t() => non_neg_integer},
          pair_effects: %{{module, atom, module} => binary},
          place: {non_neg_integer, non_neg_integer},
          readable: %{module => %{String.t() => struct}},
          tx_range: {non_neg_integer, non_neg_integer},
          verdict_ids: %{module => binary},
          whole_types: list(module),
          written: %{String.t() => MapSet.t(String.t())}
        }

  @doc """
  Returns, for each user of the given sessions, what the given effects of one batch, read from the
  given place, mean for that user - a batch holds at least one effect: keyed by the user as `Hologram.Sync.Sessions.list/0` names
  them, nil for an anonymous one.

  Every part shares what the batch is about, whoever reads it:

  - `place` - where the batch was read from, which is what a frame built from it may claim a client
    has reached
  - `tx_range` - the lowest and the highest of the batch's transaction ids
  - `checked` - every row the batch may have changed for anyone, per entity type: its own ids, both
    ends of each pair, and the rows the backwards search reaches along the read rules' and the
    verdicts' edges, packed (see `Hologram.Sync.PackedIds.pack/1`). A checked row missing from
    `readable` is one the user may not read now, or one that is gone. Packed because it goes to
    every session: a binary that size is shared between the processes it is sent to, where a set
    of ids is copied into each of them.
  - `pair_effects` - the pairs the batch added or removed, once however many times it moved each,
    keyed by `{source type, relationship name, target type}`, the name an atom, each pair packed as
    its source id and its target id (see `Hologram.Sync.PackedIds.pack_pairs/1`)
  - `verdict_ids` - the checked rows whose verdicts the batch may have moved, per entity type of
    deciding quantifiers, packed the same way: the rows it wrote, the ends of its pairs, and what
    the verdicts' edges reach
  - `own_seqs` - per replica, the highest sequence number among the batches of it the effects came
    from

  And what is the user's own:

  - `readable` - the checked rows the user may read, as they stand now, keyed by id per entity type,
    with an empty map for a checked type the user may read none of
  - `written` - per readable row, the names of the attributes the batch's puts and patches wrote, as
    the log spells them - all a patch needs, and only for a row a patch can go out for
  - `whole_types` - the entity types a grant change in the batch may have moved every row of for
    the user, which no row by row list can name

  Only the given synced types are asked about: a row of another type is never sent, and the
  backwards search follows only the edges of synced types. An effect of an entity type this node
  does not know is passed over, as the search passes it over - bar the batch it came from, which
  still counts towards its replica's number. The search and the recheck read in one snapshot, so
  they agree on what the tables hold.
  """
  @spec parts(
          list(map),
          list({pid, String.t() | nil}),
          %{{module, atom} => list(tuple)},
          list(module),
          {non_neg_integer, non_neg_integer}
        ) :: %{(String.t() | nil) => part}
  def parts(effects, sessions, edges, synced_types, place) do
    synced = MapSet.new(synced_types)
    pair_effects = pair_effects(effects, synced)

    # The rows a search finds are of the type whose edges it follows, so the edges of a type sync
    # never sends would only cost queries for rows thrown away after.
    synced_edges =
      Map.filter(edges, fn {{entity_type, _kind}, _edges} ->
        MapSet.member?(synced, entity_type)
      end)

    user_ids =
      sessions
      |> Enum.map(fn {_pid, user_id} -> user_id end)
      |> Enum.uniq()

    {:ok, {searched, verdict_searched, checked, rechecked}} =
      Connection.snapshot(fn ->
        searched = Search.candidates(effects, synced_edges)
        verdict_searched = Search.candidates(effects, synced_edges, :verdicts)

        checked =
          effects
          |> own_rows(pair_effects)
          |> merge_rows(searched.rows)
          |> merge_rows(verdict_searched.rows)
          |> Map.filter(fn {entity_type, _ids} -> MapSet.member?(synced, entity_type) end)

        {searched, verdict_searched, checked, recheck(checked, user_ids)}
      end)

    shared = %{
      checked: Map.new(checked, fn {entity_type, ids} -> {entity_type, PackedIds.pack(ids)} end),
      own_seqs: own_seqs(effects),
      pair_effects: pack_pair_effects(pair_effects),
      place: place,
      tx_range: tx_range(effects),
      verdict_ids: verdict_ids(effects, pair_effects, verdict_searched.rows, synced)
    }

    written = written(effects)

    Map.new(user_ids, fn user_id ->
      readable = readable_for(rechecked, user_id)

      part =
        Map.merge(shared, %{
          readable: readable,
          whole_types: whole_types_for(searched.whole_types, user_id),
          written: written_for(written, readable)
        })

      {user_id, part}
    end)
  end

  @doc """
  Hands the given transactions, read from the given place, to everything on this node that keeps
  clients up to date: the windows' evaluators (see `Hologram.Sync.Fanout.route/2`), and every sync
  session, each sent `{:live, part}` with its user's part of the batch (see `parts/5`).

  With no session on the node, nothing is read for them.
  """
  @spec route(list({non_neg_integer, list(map)}), {non_neg_integer, non_neg_integer}) :: :ok
  def route(transactions, place) do
    Fanout.route(transactions, place)

    case Sessions.list() do
      [] ->
        :ok

      sessions ->
        effects = Enum.flat_map(transactions, fn {_tx, events} -> events end)

        # Read from the runtime's caches rather than derived per batch, as the fan-out reads them.
        parts = parts(effects, sessions, Edges.index(), QueryCache.synced_types(), place)

        Enum.each(sessions, fn {pid, user_id} ->
          send(pid, {:live, Map.fetch!(parts, user_id)})
        end)
    end
  end

  # An id the log holds in a payload is stored as the write was given it, so it is put into the form
  # every id the log decodes has before it can be compared with one.
  defp canonical_id(id) do
    id
    |> Codec.encode(:uuid)
    |> Codec.decode(:uuid)
  end

  defp merge_rows(rows, more_rows) do
    Map.merge(rows, more_rows, fn _entity_type, ids, more_ids -> MapSet.union(ids, more_ids) end)
  end

  defp own_rows(effects, pair_effects) do
    entity_rows =
      for %{op: op, entity_id: id, type: entity_type} <- effects, op in @entity_ops do
        {entity_type, id}
      end

    pair_ends =
      Enum.flat_map(pair_effects, fn {source_type, source_id, _name, target_type, target_id} ->
        [{source_type, source_id}, {target_type, target_id}]
      end)

    entity_rows
    |> Enum.concat(pair_ends)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {entity_type, ids} -> {entity_type, MapSet.new(ids)} end)
  end

  # The batches an effect came from name their replica and number. An effect with none - a
  # command's write, a seed's, the framework's own - is nobody's.
  defp own_seqs(effects) do
    Enum.reduce(effects, %{}, fn
      %{mutation_ref: %{"replica_id" => replica_id, "seq" => seq}}, seqs ->
        Map.update(seqs, replica_id, seq, &max(&1, seq))

      _effect, seqs ->
        seqs
    end)
  end

  # A pair is written under the to-many its source type declares, so the target is of the type that
  # to-many points at. One this build has no such to-many for - a peer running a newer model can
  # write one - moves nothing it can name. Neither does a pair with an end of a type sync never
  # sends: a set is only stated for targets of synced types, by either end (see
  # `Hologram.Sync.Fill.term/2`).
  defp pair_effects(effects, synced) do
    effects
    |> Enum.filter(fn effect ->
      effect.op in @pair_ops and is_map(effect.data) and MapSet.member?(synced, effect.type)
    end)
    |> Enum.flat_map(fn %{data: data, entity_id: source_id, type: source_type} ->
      %{"relationship" => label, "target_id" => target_id} = data

      with {name, target_type} <- to_many(source_type, label),
           true <- MapSet.member?(synced, target_type) do
        [{source_type, source_id, name, target_type, canonical_id(target_id)}]
      else
        _not_named -> []
      end
    end)
    |> Enum.uniq()
  end

  defp recheck(checked, user_ids) do
    checked
    |> Enum.flat_map(fn {entity_type, ids} ->
      ids
      |> Enum.chunk_every(@recheck_chunk_size)
      |> Enum.map(&%{entity_type => &1})
    end)
    |> Enum.reduce(%{}, fn chunk, rechecked ->
      Map.merge(rechecked, Recheck.run(chunk, user_ids), fn _entity_type, rows, more_rows ->
        Map.merge(rows, more_rows)
      end)
    end)
  end

  defp pack_pair_effects(pair_effects) do
    pair_effects
    |> Enum.group_by(
      fn {source_type, _source_id, name, target_type, _target_id} ->
        {source_type, name, target_type}
      end,
      fn {_source_type, source_id, _name, _target_type, target_id} -> {source_id, target_id} end
    )
    |> Map.new(fn {key, pairs} -> {key, PackedIds.pack_pairs(pairs)} end)
  end

  defp readable_for(rechecked, user_id) do
    Map.new(rechecked, fn {entity_type, rows} ->
      readable =
        for {id, {row, readers}} <- rows, Recheck.reads?(readers, user_id), into: %{} do
          {id, row}
        end

      {entity_type, readable}
    end)
  end

  # The to-many of the given type the log names by the given label, with its target type - matched
  # as the log spells it, so nothing read from it becomes an atom.
  defp to_many(entity_type, label) do
    Enum.find_value(entity_type.__relationships__(), fn
      {name, [target_type], _opts} ->
        if Atom.to_string(name) == label, do: {name, target_type}

      _to_one ->
        nil
    end)
  end

  # The dispatcher hands over only batches holding a transaction, so there is always a range.
  defp tx_range(effects) do
    txs = Enum.map(effects, & &1.tx)

    {Enum.min(txs), Enum.max(txs)}
  end

  # Only types with a deciding quantifier send verdicts with their rows, so only their rows can
  # have verdicts move.
  defp verdict_ids(effects, pair_effects, verdict_rows, synced) do
    for {entity_type, ids} <- merge_rows(own_rows(effects, pair_effects), verdict_rows),
        MapSet.member?(synced, entity_type),
        Policy.deciding_quantifiers(entity_type) != [],
        into: %{},
        do: {entity_type, PackedIds.pack(ids)}
  end

  # A grant's holder is stored as the canonical id every write is validated to, the spelling the
  # sessions are listed by. An anonymous user holds no grant. The types are synced ones already,
  # since only the edges of those were followed.
  defp whole_types_for(_whole_types, nil), do: []

  defp whole_types_for(whole_types, user_id) do
    for {entity_type, user_ids} <- whole_types,
        MapSet.member?(user_ids, user_id),
        do: entity_type
  end

  defp written(effects) do
    Enum.reduce(effects, %{}, fn
      %{op: op, data: data, entity_id: id}, written when op in @written_ops and is_map(data) ->
        names = MapSet.new(Map.keys(data))

        Map.update(written, id, names, &MapSet.union(&1, names))

      _effect, written ->
        written
    end)
  end

  defp written_for(written, readable) do
    readable_ids =
      readable
      |> Map.values()
      |> Enum.flat_map(&Map.keys/1)

    Map.take(written, readable_ids)
  end
end
