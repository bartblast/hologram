defmodule Hologram.Sync.Live do
  @moduledoc false

  # What the dispatcher hands each batch of changes it reads: which rows the batch may have changed
  # for anyone - the rows it wrote, both ends of every pair it added or removed, and the rows whose
  # read access or verdicts it moved without writing them (see `Hologram.Sync.Search`) - who of the
  # users with a sync session on this node may read each of them now (see
  # `Hologram.Sync.Recheck`), and the pairs those rows are at an end of, which state their sets.
  # Asked once per batch for every user at once, whatever the number of sessions, and handed to
  # each session as the part that is its user's.
  #
  # What a session makes of its part - which rows its client is sent, changed or told to drop - is
  # the session's, since only it knows what its client holds.

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Oplog
  alias Hologram.DB.QueryCache
  alias Hologram.Policy
  alias Hologram.Policy.Edges
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
          moved: %{module => binary},
          overtaking_seqs: %{String.t() => non_neg_integer},
          own_puts: %{String.t() => %{module => binary}},
          own_seqs: %{String.t() => non_neg_integer},
          pair_effects: %{{module, atom, module} => binary},
          pairs: %{{module, atom, module} => binary},
          place: Oplog.place(),
          readable: %{module => %{String.t() => struct}},
          seq_range: {non_neg_integer, non_neg_integer},
          synced_types: list(module),
          verdicts: %{module => %{String.t() => %{String.t() => boolean}}},
          whole_types: list(module),
          written: %{String.t() => MapSet.t(String.t())}
        }

  @doc """
  Returns, for each user of the given sessions, what the given effects of one batch, read from the
  given place, mean for that user: keyed by the user as `Hologram.Sync.Sessions.list/0` names them,
  nil for an anonymous one. A batch holds at least one effect.

  Every part shares what the batch is about, whoever reads it:

  - `place` - where the batch was read from, which is what a frame built from it may claim a client
    has reached
  - `seq_range` - the lowest and the highest of the batch's seqs
  - `checked` - every row the batch may have changed for anyone, per entity type: its own ids, both
    ends of each pair, and the rows the backwards search reaches along the given edges - the read
    rules', and the verdicts' in a build checking permissions on the client - packed (see
    `Hologram.Sync.PackedIds.pack/1`). A checked row missing from `readable` is one the user may
    not read now, or one that is gone. Packed because it goes to every session: a binary that size
    is shared between the processes it is sent to, where a set of ids is copied into each of them.
  - `moved` - the checked rows whose read access the batch may have moved, per entity type, packed:
    the rows the backwards search reached, and the batch's own rows it created, deleted, or patched
    on an attribute their type's read rule reads. The only rows a client can have lost without its
    session knowing it held them (see `Hologram.Sync.Session`): a row the batch only renamed
    reads as it did, and a pair moves only the rows whose rules read its set, which the search
    reaches
  - `pair_effects` - the pairs the batch added or removed, once however many times it moved each,
    keyed by `{source type, relationship name, target type}`, the name an atom, each pair packed as
    its source id and its target id (see `Hologram.Sync.PackedIds.pack_pairs/1`)
  - `pairs` - every pair as it stands now that has a checked row at either end, keyed and packed
    the same way (see `pairs_touching/2`): what a row's sets are, whether a pair the batch moved is
    there now, and the pairs filed under other rows that a row arriving or leaving changes
  - `own_puts` - per replica, the rows its batches among the effects put, per entity type, packed:
    the rows it created, which its client files on its own once their batch is confirmed, so a
    session tells its client to drop the ones its user may not read, though it never told the
    client of them (see `Hologram.Sync.Pot.decide/3`)
  - `own_seqs` - per replica, the highest sequence number among the batches of it the effects came
    from
  - `overtaking_seqs` - per replica, the highest sequence number among its batches with an entry
    above the batch's (or above a given seq, see `part/6`), read in the same snapshot as the rows
    (see
    `Hologram.DB.Oplog.replica_seqs_after/1`). The rows are read after the effects, so they can
    hold a replica's batch the effects don't - and what the rows have applied of a replica's
    writes is the higher of this and `own_seqs` (see `Hologram.Sync.Session`)
  - `synced_types` - the given synced types, which decided what was asked about, so whoever reads
    the part judges it by the same ones

  And what is the user's own:

  - `readable` - the checked rows the user may read, as they stand now, keyed by id per entity type,
    with an empty map for a checked type the user may read none of
  - `verdicts` - the server's verdicts for the user on the readable rows of each type the server
    sends verdicts on (see `Hologram.Policy.verdict_operations/1`), keyed by id per entity type -
    what `Hologram.Sync.Frame.row_verdicts/2` answers for the user and the row, read in the batch's
    recheck (see `Hologram.Sync.Recheck`), so no session works one out for a batch's rows - with an
    empty map for such a type the user may read none of. In a build checking permissions on the
    client, every readable checked row of such a type has them: given the verdicts' edges, the
    backwards search finds the rows whose verdicts the batch may have moved together with those
    whose read access it may have
  - `written` - per readable row, the names of the attributes the batch's puts and patches wrote, as
    the log spells them - all a patch needs, and only for a row a patch can go out for
  - `whole_types` - the entity types a grant change in the batch may have moved every row of for
    the user, which no row by row list can name

  Only the given synced types are asked about: a row of another type is never sent, and the
  backwards search follows only the edges of synced types. An effect of an entity type this node
  does not know is passed over, as the search passes it over - bar the batch it came from, which
  still counts towards its replica's number. The search, the recheck, the pairs and the batches
  that overtook the effects read in one snapshot, so they agree on what the tables hold.
  """
  @spec parts(
          list(map),
          list({pid, String.t() | nil}),
          Edges.t(),
          list(module),
          Oplog.place()
        ) :: %{(String.t() | nil) => part}
  def parts(effects, sessions, edges, synced_types, place) do
    {:ok, parts} =
      Connection.snapshot(fn -> parts_now(effects, sessions, edges, synced_types, place) end)

    parts
  end

  @doc """
  Returns the part of the given effects that is the given user's, as `parts/5` works it out for a
  session of that user - what a returning client's catch-up decides each chunk of its gap with. The
  user is put into the spelling the node's sessions are listed by (see
  `Hologram.Auth.canonical_id/1`).

  Its `overtaking_seqs` are of the batches with an entry above the given seq rather than above the
  effects' highest. A chunk of a gap isn't bounded the way a batch is: the gap holds every effect
  committed when it was read, so a save with entries below the chunk's highest can have been
  running then, and commit before the chunk's rows are read - and the rows hold it. And a chunk can
  end inside a save, whose batches with effects only in a later chunk the rows hold too.
  """
  @spec part(
          list(map),
          String.t() | nil,
          %{{module, atom} => list(tuple)},
          list(module),
          Oplog.place(),
          non_neg_integer
        ) :: part
  def part(effects, user_id, edges, synced_types, place, overtaken_above) do
    {:ok, part} =
      Connection.snapshot(fn ->
        part_now(effects, user_id, edges, synced_types, place, overtaken_above)
      end)

    part
  end

  @doc """
  Reads what `part/6` reads in whatever transaction the caller is in, which agrees with itself only
  when that transaction reads every statement from one snapshot - what `part/6` opens.
  """
  @spec part_now(
          list(map),
          String.t() | nil,
          %{{module, atom} => list(tuple)},
          list(module),
          Oplog.place(),
          non_neg_integer
        ) :: part
  def part_now(effects, user_id, edges, synced_types, place, overtaken_above) do
    canonical_user_id = Auth.canonical_id(user_id)
    sessions = [{self(), canonical_user_id}]

    effects
    |> parts_now(sessions, edges, synced_types, place, overtaken_above)
    |> Map.fetch!(canonical_user_id)
  end

  @doc """
  Reads what `parts/5` reads in whatever transaction the caller is in, which agrees with itself only
  when that transaction reads every statement from one snapshot - what `parts/5` opens. Given a
  seq, the overtaking batches are the ones with an entry above it (see `part/6`) rather than above
  the effects' highest.
  """
  @spec parts_now(
          list(map),
          list({pid, String.t() | nil}),
          %{{module, atom} => list(tuple)},
          list(module),
          Oplog.place(),
          non_neg_integer | nil
        ) :: %{(String.t() | nil) => part}
  def parts_now(effects, sessions, edges, synced_types, place, overtaken_above \\ nil) do
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

    seq_range = seq_range(effects)

    searched = Search.candidates(effects, synced_edges)

    checked =
      effects
      |> own_rows(pair_effects)
      |> merge_rows(searched.rows)
      |> Map.filter(fn {entity_type, _ids} -> MapSet.member?(synced, entity_type) end)

    moved =
      effects
      |> moved_rows(synced_edges)
      |> merge_rows(searched.rows)
      |> Map.filter(fn {entity_type, _ids} -> MapSet.member?(synced, entity_type) end)

    rechecked = recheck(checked, user_ids)

    pairs = pairs_touching(checked, synced_types)

    {_lowest_seq, highest_seq} = seq_range
    overtaking_seqs = Oplog.replica_seqs_after(overtaken_above || highest_seq)

    shared = %{
      checked: Map.new(checked, fn {entity_type, ids} -> {entity_type, PackedIds.pack(ids)} end),
      moved: Map.new(moved, fn {entity_type, ids} -> {entity_type, PackedIds.pack(ids)} end),
      overtaking_seqs: overtaking_seqs,
      own_puts: own_puts(effects, synced),
      own_seqs: own_seqs(effects),
      pair_effects: pack_pair_effects(pair_effects),
      pairs: pairs,
      place: place,
      seq_range: seq_range,
      synced_types: synced_types
    }

    written = written(effects)

    Map.new(user_ids, fn user_id ->
      # Read once for the user rather than once for each row the batch checked.
      canonical_user_id = Auth.canonical_id(user_id)
      readable = readable_for(rechecked, canonical_user_id)

      part =
        Map.merge(shared, %{
          readable: readable,
          verdicts: verdicts_for(rechecked, readable, canonical_user_id),
          whole_types: whole_types_for(searched.whole_types, user_id),
          written: written_for(written, readable)
        })

      {user_id, part}
    end)
  end

  @doc """
  Returns the pairs, as they stand now, of every to-many whose source type and target type are both
  among the given synced types, that have one of the given rows at either end - per entity type, the
  ids of the rows. Keyed by `{source type, relationship name, target type}`, each relationship's
  pairs packed as their source id and their target id (see
  `Hologram.Sync.PackedIds.pack_pairs/1`). A relationship with no such pair is left out.

  Every pair a set of a synced type states is among them: a to-many is stated on its source, and
  the inverse of a to-many on its target, only when the other end's type is synced too (see
  `Hologram.Sync.Fill.term/2`). Read in whatever transaction the caller is in, one statement per
  relationship that a given row can be at an end of, whoever may read those rows.
  """
  @spec pairs_touching(%{module => Enumerable.t()}, list(module)) ::
          %{{module, atom, module} => binary}
  def pairs_touching(ids_by_type, synced_types) do
    synced = MapSet.new(synced_types)
    mapping = DB.mapping()

    relationships =
      for source_type <- synced_types,
          {name, [target_type], _opts} <- source_type.__relationships__(),
          MapSet.member?(synced, target_type),
          do: {source_type, name, target_type}

    # Encoded once per type rather than once per relationship it is an end of, and only for a type
    # at an end of one.
    encoded =
      ids_by_type
      |> Map.take(
        Enum.flat_map(relationships, fn {source, _name, target} -> [source, target] end)
      )
      |> Map.new(fn {entity_type, ids} ->
        {entity_type, Enum.map(ids, &Codec.encode(&1, :uuid))}
      end)

    for {source_type, name, target_type} <- relationships,
        source_ids = Map.get(encoded, source_type, []),
        target_ids = Map.get(encoded, target_type, []),
        source_ids != [] or target_ids != [],
        packed = read_pairs(mapping, source_type, name, source_ids, target_ids),
        packed != "",
        into: %{},
        do: {{source_type, name, target_type}, packed}
  end

  @doc """
  Hands the given effects, read from the given place, to every sync session on this node, each
  sent `{:live, part}` with its user's part of the batch (see `parts/5`).

  With no session on the node, nothing is read for them. In a build where no client checks
  permissions, the rows carry no verdicts, so the search follows only the read rules' edges.
  """
  @spec route(list(map), Oplog.place()) :: :ok
  def route(effects, place) do
    case Sessions.list() do
      [] ->
        :ok

      sessions ->
        # Read from the runtime's caches rather than derived per batch. A build where no client
        # checks permissions sends its rows without verdicts, so the search follows only the read
        # rules' edges.
        edges = Edges.index(QueryCache.permission_checking?())

        parts = parts(effects, sessions, edges, QueryCache.synced_types(), place)

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

  # The batch's own rows whose read access it may have moved: one it created or deleted, and one it
  # patched on an attribute its type's read rule reads - as the log spells the attribute, so nothing
  # read from it becomes an atom.
  defp moved_rows(effects, edges) do
    read_names =
      effects
      |> Enum.map(& &1.type)
      |> Enum.uniq()
      |> Map.new(&{&1, own_read_names(edges, &1)})

    effects
    |> Enum.filter(&own_row_moved?(&1, read_names))
    |> Enum.group_by(& &1.type, & &1.entity_id)
    |> Map.new(fn {entity_type, ids} -> {entity_type, MapSet.new(ids)} end)
  end

  defp own_read_names(edges, entity_type) do
    for {:attributes, names} <- Map.get(edges, {entity_type, :read}, []),
        name <- names,
        into: MapSet.new(),
        do: Atom.to_string(name)
  end

  defp own_row_moved?(%{op: op}, _read_names) when op in [:del_entity, :put_entity], do: true

  defp own_row_moved?(%{data: data, op: :patch_entity, type: entity_type}, read_names)
       when is_map(data) do
    names = Map.get(read_names, entity_type, MapSet.new())

    data
    |> Map.keys()
    |> Enum.any?(&MapSet.member?(names, &1))
  end

  defp own_row_moved?(_effect, _read_names), do: false

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

  # The rows each replica's batches put, which are the rows they created: the client's own creates,
  # and the grants a create hands its creator, whose ids the client works out the same way. Only
  # of the synced types, as every row a part names is.
  defp own_puts(effects, synced) do
    effects
    |> Enum.flat_map(fn
      %{op: :put_entity, mutation_ref: %{"replica_id" => replica_id}, type: entity_type} = effect ->
        if MapSet.member?(synced, entity_type),
          do: [{replica_id, entity_type, effect.entity_id}],
          else: []

      _effect ->
        []
    end)
    |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})
    |> Map.new(fn {replica_id, rows} ->
      by_type =
        rows
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Map.new(fn {entity_type, ids} -> {entity_type, PackedIds.pack(ids)} end)

      {replica_id, by_type}
    end)
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

  # The store is read raw: which of these pairs a user may be told about is what the rows at their
  # ends decide. The given ids come encoded.
  # sobelow_skip ["SQL.Query"]
  defp read_pairs(mapping, source_type, name, source_ids, target_ids) do
    table =
      mapping
      |> Search.join_table(source_type, name)
      |> Search.qualified_table()

    statement =
      ~s|SELECT #{PackedIds.pairs_sql(~s|"source_id"|, ~s|"target_id"|)} FROM #{table} | <>
        ~s|WHERE "source_id" = ANY($1::uuid[]) OR "target_id" = ANY($2::uuid[])|

    {:ok, %Postgrex.Result{rows: [[packed]]}} =
      Connection.query(statement, [source_ids, target_ids])

    packed
  end

  defp readable_for(rechecked, canonical_user_id) do
    Map.new(rechecked, fn {entity_type, rows} ->
      readable =
        for {id, {row, readers, _verdicts}} <- rows,
            Recheck.reads_as_canonical?(readers, canonical_user_id),
            into: %{} do
          {id, row}
        end

      {entity_type, readable}
    end)
  end

  # An effect's data leaves out the row's sequence numbers, since its own place in the log is the
  # number, so the ones its op moves are named here.
  defp sequence_names(:patch_entity), do: ["server_updated_seq"]

  defp sequence_names(:put_entity), do: ["server_created_seq", "server_updated_seq"]

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

  # The dispatcher hands over only batches holding an effect, so there is always a range.
  defp seq_range(effects) do
    seqs = Enum.map(effects, & &1.seq)

    {Enum.min(seqs), Enum.max(seqs)}
  end

  # Only types with a verdict operation send verdicts with their rows - every other row's are
  # none, which nothing has to read. Asked of the rows the user may read alone.
  defp verdicts_for(rechecked, readable, canonical_user_id) do
    for {entity_type, rows} <- rechecked,
        Policy.verdict_operations(entity_type) != [],
        into: %{} do
      verdicts =
        readable
        |> Map.fetch!(entity_type)
        |> Map.new(fn {id, _row} ->
          {_row, _readers, row_verdicts} = Map.fetch!(rows, id)

          {id, Recheck.verdicts_as_canonical(row_verdicts, canonical_user_id)}
        end)

      {entity_type, verdicts}
    end
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
        names = MapSet.new(Map.keys(data) ++ sequence_names(op))

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
