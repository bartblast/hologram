defmodule Hologram.Sync.Session do
  @moduledoc false

  # One per connected client. It keeps what that client holds and turns each batch of changes into
  # the part of it that is this client's news.
  #
  # A client arriving with nothing is filled by entity type: every row of every type sync sends
  # that its user may read, read through the type's read rules (see `Hologram.Sync.Fill`), the
  # types its page reads first, so what the client is looking at is ready first and the rest
  # arrives while it reads. A page it navigates to is then answered from what it already has, with
  # no server in the way. What changes after reaches it by read access: the session joins the
  # node's sessions (see `Hologram.Sync.Sessions`), every batch the dispatcher reads is judged for
  # all of them at once (see `Hologram.Sync.Live`), and the session tells its client what its part
  # of the batch changes of what it holds (see `Hologram.Sync.Pot`). What it keeps of that is ids,
  # never rows: the ids its client holds, and the ones it told it to drop.
  #
  # A client coming back with a place is caught up from the log (see `catch_up/1`): the effects
  # since its place, a chunk at a time, each judged the way a live batch is, once the node's gate
  # lets it in (see `Hologram.Sync.Gate`). Then it is synced by read access like a first arrival.
  #
  # The fill and the catch-up read through sync's own pool (see `Hologram.Sync.Pool`), so a wave of
  # them leaves the app's own requests alone.

  use GenServer, restart: :temporary

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Oplog
  alias Hologram.DB.QueryCache
  alias Hologram.Entity
  alias Hologram.Policy.Edges
  alias Hologram.Query.Registry
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Fill
  alias Hologram.Sync.Frame
  alias Hologram.Sync.Gate
  alias Hologram.Sync.Held
  alias Hologram.Sync.Live
  alias Hologram.Sync.Outbox
  alias Hologram.Sync.PackedIds
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.Pool
  alias Hologram.Sync.Pot
  alias Hologram.Sync.Sessions
  alias Hologram.Sync.Verdicts

  @doc """
  Starts a session for a client on the given `:page`, telling `:client` what changes for it.

  `:actor_user_id` is who the client is, or nil for an anonymous one - every row is checked
  against it before being sent, so what the client named as its page decides only the order the
  types fill in, never what it may see of them.

  `:fill_place` is where the log stood before the session began, and the place its first frames
  claim: every transaction below it finished before the session read anything, so a first
  arrival's fill holds it, and a returning client's gap covers it.

  `:policy_hash` is the hash of the rules this session judges rows by (see
  `Hologram.Policy.hash/0`), taken once where the session is started and stamped on every place a
  frame hands over: a place is a claim about what the client holds, and what it holds is what these
  rules let it see. Taken once rather than read per frame, because the rules can change under a
  running session - a live reload does that - and a place stamped with the new rules would vouch
  for rows the old ones decided.

  `:types_hash` is the hash of the entity types sync sends (see
  `Hologram.Sync.Cursor.types_hash/2`), taken where the session is started and stamped on every
  place beside the policy hash, for the same reason: a client filled with other types holds none of
  a type added since.

  `:replica_id` is the browser's own copy of the data, when the client presented one this stream
  could vouch for - it is what tells this session's frames which of the effects they carry are
  that browser's own doing. Absent for a client that presented none, and then no frame names a
  number at all.

  `:applied_seq` is how far that replica's batches had been applied when this session began. A
  session cannot work it out from the rounds it sees: the rows a returning client is told about are
  read as they stand, and the batches behind those values were applied before anything here was
  watching. Read where the replica is identified and handed over, rather than looked up here, since
  the process identifying the replica already reads the database for it. A first arrival's fill
  reads the number again with its rows, and never names one below this.

  A frame carries the place the client may resume from only once it holds a whole pot: mid-fill
  there is nothing coherent to resume from, and a place handed over early is a claim the client
  cannot honour.

  A client arriving with nothing is filled at once, after the session joins the node's sessions:
  every batch read after that reaches the session, and the fill, read after it, holds every
  transaction committed before. Each type ends with a marker saying the client holds all of it, and
  the last with one saying it holds everything, dated by `:fill_place`. A batch the session
  handles after the fill claims the place it was read from, and one that committed wholly before
  `:fill_place` is passed over: the fill holds it, and its rows can be older than the fill's.

  `:read_gap` reads what a returning client missed - absent for one arriving with nothing, in which
  case every row it may see is sent. It answers what `Hologram.Sync.Catchup.gap/4` answers: the
  effects since the client's place and the edge below which they hold every transaction, or why it
  has to be sent everything again, which ends the session with `{:full_resync, reason}` so the
  client comes back through the doors. Given one, the client keeps what it already holds and is told
  what the gap changed of it. Handed over as a reader rather than as the effects, because the gap is
  read only once the session has joined the node's sessions - a change committed before then is in
  the gap, and one committed after reaches the session as a batch - and the read runs in this
  process. Whether a gap can be had at all is decided before the session starts, since it is a
  question about the log rather than about this client - the session's own read finding it can't
  is the log having moved since, a gap that outgrew a replay or a deploy landing in between.

  `:read_fill` reads what a client arriving with nothing is sent of one entity type, answering what
  `Hologram.Sync.Fill.read/4` answers, which it defaults to. Handed over as a reader for the same
  reason `:read_gap` is: the read runs in this process, and what it runs in is the caller's to say.

  `:read_ids` reads, for a returning client, the ids of the rows of one entity type its user may
  read, packed, answering what `Hologram.Sync.Fill.read_ids/2` answers, which it defaults to - a
  reader for the same reason.

  `:read_part` reads, for a returning client, its user's part of one chunk of the gap, answering
  what `Hologram.Sync.Live.part/6` answers, which it defaults to - a reader for the same reason.

  `:outbox` holds the options of the outbox frames go out through, none by default (see
  `Hologram.Sync.Outbox.new/2`).
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @impl GenServer
  def init(opts) do
    # Read once and asked about once: whether this client is resuming IS whether it arrived with a
    # gap to read, and two reads of the same option are two chances for them to say different
    # things.
    read_gap = Keyword.get(opts, :read_gap)
    resuming = read_gap != nil
    client = Keyword.fetch!(opts, :client)

    state = %{
      actor_user_id: Keyword.get(opts, :actor_user_id),
      announced: MapSet.new(),
      applied_seq: Keyword.get(opts, :applied_seq),
      cut: nil,
      # The salt a returning client's catch-up hashes the rows it may hold and lost by (see
      # `tell_part/3`), one per session, so every frame of the catch-up and the batches after it
      # hash alike, and the client works the hashes of what it holds out once.
      drop_salt: if(resuming, do: Frame.drop_salt()),
      fill_place: Keyword.get(opts, :fill_place),
      gate_ref: nil,
      grants_kept: nil,
      outbox: Outbox.new(client, Keyword.get(opts, :outbox, [])),
      page: Keyword.fetch!(opts, :page),
      page_types: MapSet.new(),
      # A returning client's frames claim no place until a chunk of its gap is told: until then it
      # is where it came back from.
      place: if(resuming, do: nil, else: Keyword.get(opts, :fill_place)),
      policy_hash: Keyword.fetch!(opts, :policy_hash),
      pot: Pot.new(),
      read_fill: Keyword.get(opts, :read_fill, &Fill.read/4),
      read_gap: read_gap,
      read_ids: Keyword.get(opts, :read_ids, &Fill.read_ids/2),
      read_part: Keyword.get(opts, :read_part, &Live.part/6),
      replica_id: Keyword.get(opts, :replica_id),
      resuming: resuming,
      told_verdicts: %{},
      trust_edge: nil,
      types_hash: Keyword.fetch!(opts, :types_hash),
      unsent: nil
    }

    # Watched as well as linked, through the outbox: a link takes this session down only with a
    # client that crashes, and one that ends normally would leave it among the node's sessions,
    # judged for and sent every batch for nobody.
    {:ok, state, {:continue, :subscribe}}
  end

  # A client arriving with nothing joins the sessions every batch is judged for before anything is
  # read, so every batch read after it reaches this session, and the fill - read after it - holds
  # everything committed before.
  @impl GenServer
  def handle_continue(:subscribe, %{resuming: false} = state) do
    :ok = Sessions.register(state.actor_user_id)

    {:noreply, Pool.run(fn -> fill(%{state | page_types: page_types(state.page)}) end)}
  end

  # A returning client waits its turn at the node's gate. It hasn't joined the node's sessions yet,
  # so no batch reaches it meanwhile, and waiting costs the node nothing but the wait.
  def handle_continue(:subscribe, state) do
    {:noreply, %{state | gate_ref: Gate.ask()}}
  end

  # What the process reports of itself - to `:sys.get_status/1`, and in the report a crash or a
  # cut writes - leaves out the values of the batch it was reading, which are every client's. A log
  # is no place for them.
  @impl GenServer
  def format_status(status), do: redact_message(status)

  defp redact_message(%{message: {:live, _part}} = status) do
    %{status | message: {:live, :redacted}}
  end

  defp redact_message(status), do: status

  @impl GenServer
  def handle_info({:cut, reason}, state) do
    {:stop, reason, state}
  end

  # What this session is linked to went away - the connection, or the session list a restart of the
  # sync unit replaced - and the session goes with it. Only reached by a session trapping exits; one
  # that doesn't is taken down by the link itself.
  def handle_info({:EXIT, _from, reason}, state) do
    {:stop, reason, state}
  end

  def handle_info({:live, _part}, %{cut: cut} = state) when cut != nil do
    {:noreply, state}
  end

  # A data model under a hold (see Hologram.Entity.Model.hold/0) can't be judged against until it
  # is released, and a part can be queued before a hold begins. The session ends rather than
  # telling half of it, and the client comes back through the doors once the model is released.
  def handle_info({:live, part}, state) do
    state
    |> tell_part_unless_filled(part)
    |> noreply_sleeping_when_idle()
  rescue
    Hologram.StaleModelError -> {:stop, {:shutdown, :model_held}, state}
  end

  # The client went (see `Hologram.Sync.Outbox`), and there is no one left to tell anything.
  def handle_info({:DOWN, ref, :process, _client, _reason}, state)
      when ref == state.outbox.client_ref do
    {:stop, :normal, state}
  end

  # The gate went while the client waited its turn, which nothing will now give it. It comes back
  # through the doors and waits at the gate that replaced this one.
  def handle_info({:DOWN, ref, :process, _gate, _reason}, state) when ref == state.gate_ref do
    {:stop, {:shutdown, :gate_gone}, state}
  end

  # The client's turn to be caught up. It leaves the gate once caught up, and sleeps after it: what
  # the catch-up read is garbage by then, and a session can sit idle for as long as its client
  # stays, with nothing allocating to collect it.
  def handle_info({:gate, :open}, state) do
    caught_up = Pool.run(fn -> catch_up(state) end)

    Process.demonitor(state.gate_ref, [:flush])
    :ok = Gate.leave()

    {:noreply, %{caught_up | gate_ref: nil}, :hibernate}
  end

  # The stream serving this client replaced it on a change of identity. It asks rather than stops
  # it, since this session may be waiting on that very stream (see `Hologram.Sync.Outbox.put/2`),
  # and a session waiting there takes the ask itself.
  def handle_info(:sync_stop, state) do
    {:stop, :normal, state}
  end

  # The stream wrote a chunk while nothing here was waiting to hear it.
  def handle_info(:sync_written, state) do
    {:noreply, %{state | outbox: Outbox.written(state.outbox)}}
  end

  # A part's packed ids are shared with every session it went to, and a session holds onto them
  # until it next collects its garbage - which an idle one never does. So one with nothing else to
  # read sleeps, collecting as it goes.
  defp noreply_sleeping_when_idle(state) do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, 0} -> {:noreply, state, :hibernate}
      _more_to_read -> {:noreply, state}
    end
  end

  # The marker carries the place, and the place is computed from the state that ALREADY records
  # the pot as announced - `cursor/1` answers nil until the client holds a whole pot, and
  # announcing `:all` is precisely what makes that true. Computed from `state` instead, the frame
  # that says "you have everything" would be the one frame unable to say where everything ends.
  defp announce_all(state) do
    if MapSet.member?(state.announced, :all) do
      state
    else
      announced = %{state | announced: MapSet.put(state.announced, :all)}

      tell_client(announced, {:sync_synced, :all, cursor(announced)})
    end
  end

  # Every synced type the client may see rows of, the page's own first, each sent whole and then
  # declared complete - per type rather than per page, because what a type's marker says is true
  # on every page. The rows travel with no place, since mid-fill the client holds no whole pot, and
  # with the number read beside them (see `Hologram.Sync.Fill.read/4`).
  #
  # Each type's rows are held as they go out. A set a row goes out with names every row of its
  # type the user may read when the row is read, and a row of a type read later can be gone or
  # hidden by then and never reach the client - so the rows the sets name that the client never got
  # are kept among the ones it was told to drop, and a later removal of a pair naming one is told.
  defp fill(state) do
    synced_types = QueryCache.synced_types()

    page_types =
      state.page_types
      |> MapSet.intersection(MapSet.new(synced_types))
      |> Enum.sort()

    fill_order = page_types ++ (synced_types -- page_types)

    # A session cut while filling reads no further type: nothing it reads would reach the client.
    {filled, named} =
      Enum.reduce_while(fill_order, {state, %{}}, fn entity_type, {acc, named} ->
        if acc.cut do
          {:halt, {acc, named}}
        else
          {:cont, fill_type(acc, named, entity_type, synced_types)}
        end
      end)

    pot =
      Enum.reduce(named, filled.pot, fn {entity_type, packed_ids}, acc ->
        {_held, not_held} = Held.split(acc.held, entity_type, packed_ids)

        Pot.drop(acc, entity_type, PackedIds.unpack(not_held))
      end)

    # The rows read are garbage now, and a session can sit idle for as long as its client stays,
    # with nothing allocating to collect them.
    :erlang.garbage_collect()

    # Read once every type is: what a transaction below it wrote may be in the rows of some types
    # and not in those read before it committed (see `trusts_held?/2`).
    announce_all(%{filled | pot: pot, trust_edge: Oplog.current_xmax()})
  end

  # TODO: a client cut off mid-fill comes back with no place and is filled from nothing, though it
  # holds every type whose marker it got. Settle against the local store's design whether a place
  # per type is worth giving it.
  defp fill_type(state, named, entity_type, synced_types) do
    {rows, read_seq} =
      state.read_fill.(entity_type, state.actor_user_id, state.replica_id, synced_types)

    # Never below what the session already knew: every batch that number counts committed before
    # the read, so its writes are in these rows too.
    applied_seq = higher_seq(state.applied_seq, read_seq)

    told =
      rows
      |> Enum.chunk_every(Catchup.rows_per_frame())
      |> Enum.reduce_while(%{state | applied_seq: applied_seq}, fn chunk, acc ->
        deltas = Enum.map(chunk, &Frame.put_entity(&1, Frame.row_verdicts(acc.actor_user_id, &1)))

        told_chunk =
          acc
          |> tell_client({:sync_deltas, nil, deltas, applied_seq})
          |> remember_verdicts(deltas)

        if told_chunk.cut, do: {:halt, told_chunk}, else: {:cont, told_chunk}
      end)

    marked = tell_client(told, {:sync_synced, {:types, [entity_type]}, nil})

    pot = Pot.hand_over(marked.pot, entity_type, Enum.map(rows, & &1.id))

    {%{marked | pot: pot}, name_set_members(rows, named)}
  end

  # The rows the sets of the given rows name, added to the given ones per entity type - kept packed,
  # since they last until the fill ends.
  defp name_set_members(rows, named) do
    rows
    |> Enum.flat_map(&set_members/1)
    |> Enum.group_by(& &1.__struct__, & &1.id)
    |> Enum.reduce(named, fn {entity_type, ids}, acc ->
      Map.update(acc, entity_type, PackedIds.pack(ids), &PackedIds.insert(&1, ids))
    end)
  end

  defp set_members(row) do
    row.__struct__
    |> Entity.includable_names()
    |> Enum.flat_map(fn name ->
      case Map.fetch!(row, name) do
        members when is_list(members) -> members
        _not_a_set -> []
      end
    end)
  end

  # A returning client joins the node's sessions first, so every batch read after it reaches the
  # session, and the gap, read after that, holds every one committed before. Before the gap it reads
  # what its user may read now, which it takes the client to hold: a row the user loses after that
  # read is in the gap or in a batch after it, and either finds it held and takes it away. But what
  # the session takes the client to hold is read, not known - a row the user may read now can be one
  # the client never got - so every row the gap reaches that the user may read is handed over whole.
  # And a row the client holds that its user lost before the read is missing from it, so every row
  # the gap may have moved out of the user's reach that the session doesn't take the client to hold
  # is told by hash (see `Hologram.Sync.Frame.unsync_hashed/3`): the client drops it if it has it,
  # and learns nothing of it if not. Grants are the exception, told by the list of the ones the
  # client may keep (see `tell_part/3`).
  #
  # The batches that reach the session meanwhile queue behind this callback, and are told after it
  # (see `trusts_held?/2`).
  defp catch_up(state) do
    :ok = Sessions.register(state.actor_user_id)

    held = read_held(state)

    case held.read_gap.() do
      {:ok, gap, edge} ->
        held
        |> tell_gap(gap, edge)
        |> caught_up(edge)

      {:full_resync, reason} ->
        cut(held, {:full_resync, reason})
    end
  rescue
    Hologram.StaleModelError -> cut(state, {:shutdown, :model_held})
  end

  defp read_held(state) do
    held =
      Enum.reduce(QueryCache.synced_types(), Held.new(), fn entity_type, acc ->
        Held.put(acc, entity_type, state.read_ids.(entity_type, state.actor_user_id))
      end)

    %{state | pot: Pot.from_held(held)}
  end

  # The gap is told a chunk at a time, in log order, each chunk judged as a live batch is and claiming
  # the place of its last effect, so a client cut off mid catch-up comes back after the chunks it
  # got. Every chunk's rows are read after the gap was, so they hold every later chunk's effects too:
  # a row an earlier chunk settled - handed over or dropped - is passed over by the later ones, and a
  # row written many times while the client was away goes out once.
  #
  # A type a grant moved whole for the user is read again once, in the chunk that first names it:
  # read after the gap, it holds every later grant change too. When the gap takes a grant of the
  # user's away, the rows it hid can't be listed without reading the whole type, so the client is
  # told which rows of the type it may keep instead, by hash (see `reread_type/5`).
  defp tell_gap(state, gap, edge) do
    context = %{
      edge: edge,
      # As the dispatcher reads its batches (see `Hologram.Sync.Live.route/2`): a build where no
      # client checks permissions sends rows without verdicts, so the search follows only the read
      # rules' edges.
      edges: Edges.index(QueryCache.permission_checking?()),
      keep_salt: if(grant_lost?(gap, state.actor_user_id), do: state.drop_salt),
      synced_types: QueryCache.synced_types()
    }

    {told, _settled, _reread} =
      gap
      |> Enum.chunk_every(Catchup.rows_per_frame())
      |> Enum.reduce_while({state, Held.new(), MapSet.new()}, fn chunk, {acc, settled, reread} ->
        if acc.cut do
          {:halt, {acc, settled, reread}}
        else
          {:cont, tell_chunk(acc, {settled, reread}, chunk, context)}
        end
      end)

    told
  end

  # Whether the gap deletes a grant held by the given user. Grants are only ever created and
  # deleted, never patched, so a deleted one is all that takes one away. Asked of the log about the
  # gap's grant deletes alone, without reading their payloads back, so it costs what those few
  # effects cost whatever the size of the gap. A delete records the row as decoded from its columns,
  # so a grant names its user in the one spelling a uuid decodes to, which
  # `Hologram.Auth.canonical_id/1` gives too.
  defp grant_lost?(_gap, nil), do: false

  defp grant_lost?(gap, actor_user_id) do
    seqs = for %{op: :del_entity, seq: seq, type: RoleGrant} <- gap, do: seq

    Oplog.any_data_match?(seqs, %{"user_id" => Auth.canonical_id(actor_user_id)})
  end

  # The chunk's rows are read after the gap, so they can hold a batch of this client's in a
  # transaction at or above the edge that the gap's read found still open - one below the chunk's
  # highest included - and the frames have to claim it (see `tell_part/3`). They can also hold a
  # batch in the chunk's highest transaction whose effects a later chunk holds, so that transaction
  # counts too.
  defp tell_chunk(state, {settled, reread}, chunk, context) do
    effects = with_data(chunk)
    place = chunk_place(chunk, context.edge)
    %{tx: highest_tx} = Enum.max_by(chunk, & &1.tx)
    overtaken_above = min(highest_tx, context.edge) - 1

    read =
      state.read_part.(
        effects,
        state.actor_user_id,
        context.edges,
        context.synced_types,
        place,
        overtaken_above
      )

    part = %{
      without_settled(read, settled)
      | whole_types: Enum.reject(read.whole_types, &MapSet.member?(reread, &1))
    }

    told = tell_part(state, part, trust_held?: false, keep_salt: context.keep_salt)

    # A type read again is settled whole: every row of it the user may read went out, and the
    # session takes the client to hold exactly those.
    reread_settled =
      Enum.reduce(part.whole_types, settle(settled, part, state.pot), fn entity_type, acc ->
        Held.add(acc, entity_type, Held.ids(told.pot.held, entity_type))
      end)

    {told, reread_settled, MapSet.union(reread, MapSet.new(part.whole_types))}
  end

  # The gap is read without payloads, which keeps its size a count (see `Hologram.Sync.Catchup`),
  # and the backwards search reads them, so they are read for one chunk at a time.
  defp with_data(chunk) do
    data =
      chunk
      |> Enum.filter(&is_nil(&1.data))
      |> Enum.map(& &1.seq)
      |> Oplog.read_data()

    Enum.map(chunk, fn effect -> %{effect | data: Map.get(data, effect.seq, effect.data)} end)
  end

  # The place of a chunk's last effect, or the edge when that is lower: a transaction below the
  # effect can have been open when the gap was read, and commit after, while every one below the
  # edge had finished. Claiming the edge replays the effects at and above it, which hands their rows
  # over again and loses nothing.
  defp chunk_place(chunk, edge) do
    %{seq: seq, tx: tx} = List.last(chunk)

    min({tx, seq}, {edge, 0})
  end

  # The rows of a chunk an earlier one already settled, taken out of its part. Its pairs stay: a
  # pair the chunk moved is told under the rows the client holds, whichever chunk handed them over.
  defp without_settled(part, settled) when map_size(settled) == 0, do: part

  defp without_settled(part, settled) do
    unsettled = fn entity_type, rows ->
      Map.reject(rows, fn {id, _value} -> Held.member?(settled, entity_type, id) end)
    end

    unsettled_ids = fn packed_by_type ->
      Map.new(packed_by_type, fn {entity_type, packed_ids} ->
        {_settled, rest} = Held.split(settled, entity_type, packed_ids)

        {entity_type, rest}
      end)
    end

    %{
      part
      | checked: unsettled_ids.(part.checked),
        moved: unsettled_ids.(part.moved),
        readable: Map.new(part.readable, fn {type, rows} -> {type, unsettled.(type, rows)} end),
        verdicts: Map.new(part.verdicts, fn {type, rows} -> {type, unsettled.(type, rows)} end)
    }
  end

  # What a chunk settled, given what the session took the client to hold before it: every row the
  # user may read is handed over whole, every held row it checked that the user may not is
  # dropped, and every other row it may have moved out of the user's reach is told by hash.
  defp settle(settled, part, pot) do
    Enum.reduce(part.checked, settled, fn {entity_type, packed_ids}, acc ->
      {held, _not_held} = Held.split(pot.held, entity_type, packed_ids)

      readable_ids =
        part.readable
        |> Map.get(entity_type, %{})
        |> Map.keys()

      moved_ids =
        part.moved
        |> Map.get(entity_type, "")
        |> PackedIds.unpack()

      Held.add(acc, entity_type, readable_ids ++ PackedIds.unpack(held) ++ moved_ids)
    end)
  end

  # Once the gap is told, the client holds what every transaction below the edge wrote, so the
  # marker claims the edge. A batch with a transaction below the edge read now can be in some of what
  # the catch-up read and not in the rest, so it hands its rows over whole (see `trusts_held?/2`).
  defp caught_up(state, edge) do
    announce_all(%{
      state
      | place: max_place(state.place, {edge, 0}),
        read_gap: nil,
        trust_edge: Oplog.current_xmax()
    })
  end

  # The session ends once what is already queued ahead of the message has been read, so every
  # caller of this can carry on returning state.
  defp cut(state, reason) do
    send(self(), {:cut, reason})

    %{state | cut: reason}
  end

  # Every frame and marker goes out through the outbox, which encodes it for the client's stream and
  # waits while the client is behind (see `Hologram.Sync.Outbox`).
  #
  # A session cut tells nothing more: it stops once the cut message is read, and the client is told
  # again, filled or caught up, when it comes back through the doors. A client that took nothing
  # for as long as the outbox waits is cut, and a stream asking the session to stop has it end as
  # it would have between messages.
  defp tell_client(%{cut: cut} = state, _message) when cut != nil, do: state

  defp tell_client(state, message) do
    case Outbox.put(state.outbox, message) do
      {:ok, outbox} -> %{state | outbox: outbox}
      :stalled -> cut(state, :client_stalled)
      :stopped -> cut(state, :normal)
    end
  end

  # What a frame may claim the client has reached. Synced by read access, it is the place the
  # latest batch the session handled was read from - one place, whatever rows the batch touched -
  # and the fill's place before any. A client cut off mid-batch replays that batch.
  defp cursor(state) do
    case {holds_a_whole_pot?(state), state.place} do
      {true, {tx, seq}} -> Cursor.encode(tx, seq, state.policy_hash, state.types_hash)
      _no_place -> nil
    end
  end

  # A cursor is a CLAIM - "everything up to here is applied" - and the server takes it at face
  # value on the way back, replaying only what came after. A client part way through its first fill
  # cannot make that claim: it holds some types and not others, and handing it a place would have
  # it come back asking for the little that changed since, never learning about the types it
  # never received. Silently, and for as long as it keeps that store.
  #
  # So frames carry no place until the client has a whole pot to date it - which is true from the
  # start for one that arrived WITH a gap, since it kept what it already had, and true for a first
  # arrival once its fill has ended.
  defp holds_a_whole_pot?(state) do
    state.resuming or MapSet.member?(state.announced, :all)
  end

  # Nil is "no number", never zero: a replica that has had nothing applied and one this stream
  # cannot name are both spoken of by saying nothing.
  defp higher_seq(nil, seq), do: seq

  defp higher_seq(seq, nil), do: seq

  defp higher_seq(left, right), do: max(left, right)

  # What a frame told of the server's verdicts, kept so a later batch tells only what moved.
  defp remember_verdicts(state, frame_deltas) do
    %{state | told_verdicts: Verdicts.remember(state.told_verdicts, frame_deltas)}
  end

  # A batch can hand over many rows at once - a grant or a related row moving brings every row
  # leaning on it - and all of them in one frame is a frame of unbounded size, the memory it costs
  # unbounded in exactly the way a replay's was. Rows that APPEARED are the part that
  # grows, so they are split across frames and everything else rides with the first.
  defp split_news(news) do
    case Enum.chunk_every(news.appeared, Catchup.rows_per_frame()) do
      [] ->
        if news == %{appeared: [], edges: [], patched: [], unsynced: []}, do: [], else: [news]

      [first | rest] ->
        [%{news | appeared: first}] ++
          Enum.map(rest, &%{appeared: &1, edges: [], patched: [], unsynced: []})
    end
  end

  # A batch whose every transaction committed before a first arrival's fill place is one the fill
  # read, and its rows can be older than the fill's, so it is passed over. A returning client's
  # catch-up holds only the rows its gap names, so every batch is told it.
  defp tell_part_unless_filled(
         %{fill_place: {fill_tx, _seq}, resuming: false} = state,
         %{tx_range: {_lowest, highest}}
       )
       when highest < fill_tx do
    state
  end

  defp tell_part_unless_filled(state, part), do: tell_part(state, part)

  # The entity types the page's windows read, which the fill sends first. Read from the terms the
  # build gave the windows; nothing is subscribed to.
  defp page_types(page) do
    page
    |> PageWindows.lookup()
    |> Enum.map(&QueryCache.window/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(MapSet.new(), &MapSet.union(&2, Registry.entity_types(&1)))
  end

  # A type read again whole for this user, because a grant moved what it may read of every row of
  # it, and what that tells the client - in frames of its own, after the batch's, since a frame's
  # deltas are applied grouped by kind rather than in the order they were worked out.
  #
  # Given a salt, the client is also told every row of the type it may keep, by hash, and drops the
  # rest: for a returning client whose user lost a grant, where a row the grant hid can be held
  # without the session knowing. One list, in a frame of its own claiming no number - a client
  # dropping every row missing from part of a list would drop the rest of it. A row of the type the
  # client's own batch creates after the read, its answer filing it before this frame lands, goes
  # with the rest until that batch is told, once the catch-up is over.
  defp reread_type(entity_type, state, synced_types, trust_held?, keep_salt) do
    {rows, read_seq} =
      state.read_fill.(entity_type, state.actor_user_id, state.replica_id, synced_types)

    read_pairs = &Live.pairs_touching(&1, synced_types)

    {news, pot} =
      Pot.reread(state.pot, entity_type, rows, read_pairs, trust_held?: trust_held?)

    # Read after the batch, so its rows can hold batches of this client's the session hasn't told:
    # their frames claim the number the read found, and the session keeps its own (see
    # `tell_part/3`).
    %{state | pot: pot}
    |> send_news(news, %{}, higher_seq(state.applied_seq, read_seq))
    |> send_keep(entity_type, keep_salt, rows)
  end

  defp send_keep(state, _entity_type, nil, _rows), do: state

  defp send_keep(state, entity_type, salt, rows) do
    send_keep_ids(state, entity_type, salt, Enum.map(rows, & &1.id))
  end

  defp send_keep_ids(state, entity_type, salt, ids) do
    keep = Frame.keep_hashed(entity_type, salt, ids)

    state
    |> send_unsent(nil)
    |> Map.put(:unsent, {[keep], nil})
  end

  # Frames carrying the given news, the rows handed over split across them by the frame size and
  # everything else riding the first (see `split_news/1`). A row handed over carries the given
  # verdicts for it, or has them worked out when none are given - a reread type's rows, read
  # after the batch.
  #
  # The frames claim the given number. One above the session's own is a claim about rows read with
  # this client's later batches in them, which holds for the rows handed over whole and not for a
  # pair filed under a row the client already holds: the client takes a pair as a write to that
  # row, which isn't restated. So the pairs go in a frame of their own, under the session's number -
  # a pair applied twice changes nothing.
  #
  # The rows told by hash go in frames of their own, claiming no number at all: the client drops
  # what it holds of them and of the sets naming them under rows these frames don't restate, and a
  # number would have it take its own writes to those rows as being in what it holds.
  defp send_news(state, news, verdicts, claim) do
    {hidden, rows_news} = Map.pop(news, :hidden, [])

    state
    |> send_rows(rows_news, verdicts, claim)
    |> send_hidden(hidden)
  end

  defp send_rows(state, %{edges: edges} = news, verdicts, claim)
       when claim != state.applied_seq and edges != [] do
    state
    |> send_frames(%{news | edges: []}, verdicts, claim)
    |> send_frames(
      %{appeared: [], edges: edges, patched: [], unsynced: []},
      verdicts,
      state.applied_seq
    )
  end

  defp send_rows(state, news, verdicts, claim), do: send_frames(state, news, verdicts, claim)

  # Split by the frame size as the rows handed over are, so no frame carries more hashes than it
  # would rows.
  defp send_hidden(state, hidden) do
    hidden
    |> Enum.flat_map(fn {entity_type, salt, ids} ->
      ids
      |> Enum.chunk_every(Catchup.rows_per_frame())
      |> Enum.map(&{entity_type, salt, &1})
    end)
    |> Enum.reduce(state, fn entry, acc ->
      news = %{appeared: [], edges: [], hidden: [entry], patched: [], unsynced: []}

      acc
      |> send_unsent(nil)
      |> Map.put(:unsent, {Frame.deltas(news, acc.actor_user_id), nil})
    end)
  end

  # Only the batch's last frame carries its place. The client keeps each frame's cursor as the frame
  # lands, so an earlier frame carrying it would have a client cut off after that frame come back
  # past the rest of the batch, which it would then never get. The others carry none, which leaves
  # the client where it was: one cut off among them replays the batch. So each frame is held back
  # until the next one is worked out, and the last until the batch is over (see `flush_frames/1`).
  defp send_frames(state, news, verdicts, claim) do
    news
    |> split_news()
    |> Enum.reduce(state, fn frame_news, acc ->
      frame_deltas = Frame.deltas(frame_news, acc.actor_user_id, verdicts)

      acc
      |> send_unsent(nil)
      |> Map.put(:unsent, {frame_deltas, claim})
      |> remember_verdicts(frame_deltas)
    end)
  end

  # Sends the batch's last frame, with the batch's place.
  defp flush_frames(state), do: send_unsent(state, cursor(state))

  defp send_unsent(%{unsent: nil} = state, _cursor), do: state

  defp send_unsent(%{unsent: {deltas, claim}} = state, cursor) do
    tell_client(%{state | unsent: nil}, {:sync_deltas, cursor, deltas, claim})
  end

  # What one batch tells this client: where it leaves it, how far its own batches are in, what the
  # batch changed of what it holds and may read (see `Hologram.Sync.Pot.decide/3`), the verdicts it
  # moved, and then the types a grant moved whole.
  #
  # The rows were read after the batch, so they can hold a later batch of this client's own that the
  # batch doesn't. The client takes a frame's number to cover every write of its own to the rows the
  # frame names, so a frame naming a row with that batch in it has to claim that batch, or the client
  # shows the batch's writes twice - and a patch carries only the attributes the batch wrote, so a
  # patch claiming it would drop what the client shows of the batch's other writes. So a part a
  # later batch of this client's overtook hands its rows over whole, as read with that batch in them,
  # under that batch's number. The session keeps the number of what it was told: the next part is
  # judged against it, so one the same later batch overtook goes out whole too. The fill raises it
  # from its own reads, and the catch-up from the batches its chunks hold, each chunk claiming its
  # own overtaking number in its frames - which is safe because the edge is read after them: a part
  # such a batch can overtake starts below the edge, and goes out whole (see `trusts_held?/2`).
  #
  # Given `trust_held?: false`, every row the user may read is handed over whole whatever the
  # session takes the client to hold - a catch-up's chunk, whose held ids were read rather than told.
  # A returning client's session also tells such a part's rows the user may have lost by hash, as
  # it does one with a transaction below the edge read after the catch-up: a change after the gap
  # was read can take a hidden row out of reach of a chunk's search - a task its project's going
  # private hid moving to another private project before the chunk walks the tables - and the
  # change's own batch then finds the row hidden and not held.
  defp tell_part(state, part, opts \\ []) do
    own_seq = state.replica_id && Map.get(part.own_seqs, state.replica_id)
    overtaking_seq = state.replica_id && Map.get(part.overtaking_seqs, state.replica_id)

    placed = %{
      state
      | applied_seq: higher_seq(state.applied_seq, own_seq),
        place: max_place(state.place, part.place)
    }

    overtaken? = overtaken?(placed.applied_seq, overtaking_seq)
    trust_given? = Keyword.get(opts, :trust_held?, true)
    trust_held? = trust_given? and trusts_held?(placed, part) and not overtaken?
    hidden_salt = unless trust_given? and trusts_held?(placed, part), do: state.drop_salt

    {news, pot} =
      Pot.decide(placed.pot, part, trust_held?: trust_held?, hidden_salt: hidden_salt)

    stale = stale_verdicts(placed, part, trust_held?)

    decided = %{placed | pot: pot}
    claim = if overtaken?, do: overtaking_seq, else: placed.applied_seq

    # A grant's id is worked out from who holds which role on what (see
    # `Hologram.Auth.RoleGrant`), so a client could hash the grants it guesses and learn which of
    # them exist. Grants are told by a list of the ones the client may keep instead, which names
    # only grants it may read (see `keep_grants/3`).
    {grants_hidden, hidden} = Enum.split_with(news.hidden, &(elem(&1, 0) == RoleGrant))

    news_with_verdicts = %{
      news
      | hidden: hidden,
        patched: Verdicts.patches(news.patched, stale)
    }

    told =
      decided
      |> send_news(news_with_verdicts, part.verdicts, claim)
      |> keep_grants(grants_hidden, hidden_salt)

    # A reread is judged by the edge alone: its frames claim its own read's number, so a later
    # batch of this client's that overtook the part leaves its rows as true as they are.
    reread_trust? = trust_given? and trusts_held?(placed, part)

    keep_salt = Keyword.get(opts, :keep_salt)

    part.whole_types
    |> Enum.reduce(told, &reread_type(&1, &2, part.synced_types, reread_trust?, keep_salt))
    |> flush_frames()
  end

  # Read as they stand, rather than taken from what the session holds of them: a grant the client's
  # own write made meanwhile - a creator's, which the browser files the moment its write is
  # answered - may be in no part the session has told yet, and a list without it would have the
  # client drop it. One the write makes between this read and the list landing is still dropped,
  # until the write's own batch hands it over, after the catch-up.
  #
  # Once per session. Every grant a list leaves out that the client may hold is one its user could
  # not read when the session read what the client holds, since the session holds every other one
  # and drops it by id when it goes. A grant the list names that the session doesn't hold - one its
  # user could read when the list was read - is kept (`grants_kept`), and dropped by id should a
  # later part hide it: naming a grant its user could read tells the client nothing.
  defp keep_grants(state, [], _salt), do: state

  defp keep_grants(%{grants_kept: nil} = state, _grants_hidden, salt) do
    ids =
      RoleGrant
      |> state.read_ids.(state.actor_user_id)
      |> PackedIds.unpack()

    held =
      state.pot.held
      |> Held.ids(RoleGrant)
      |> MapSet.new()

    listed = MapSet.new(ids)

    # A grant the session holds that the list leaves out - one a change not told yet hid - is one
    # the client drops, so the session no longer holds it either, and hands it over whole should it
    # come back.
    pot = Pot.drop(state.pot, RoleGrant, Enum.sort(MapSet.difference(held, listed)))

    %{
      send_keep_ids(state, RoleGrant, salt, ids)
      | grants_kept: MapSet.difference(listed, held),
        pot: pot
    }
  end

  defp keep_grants(state, grants_hidden, _salt) do
    named =
      grants_hidden
      |> Enum.flat_map(fn {_type, _salt, ids} -> ids end)
      |> MapSet.new()
      |> MapSet.intersection(state.grants_kept)

    if MapSet.size(named) == 0 do
      state
    else
      deltas =
        named
        |> Enum.sort()
        |> Enum.map(&Frame.unsync_entity(&1, RoleGrant))

      state
      |> send_unsent(nil)
      |> Map.put(:unsent, {deltas, nil})
      |> Map.put(:grants_kept, MapSet.difference(state.grants_kept, named))
    end
  end

  # A row handed over whole travels with its verdicts, and none held is patched when held isn't
  # trusted. The verdicts are the part's, read in the batch's recheck.
  defp stale_verdicts(state, part, true = _trust_held?) do
    state.pot
    |> Pot.verdict_rows(part)
    |> Verdicts.moved(state.told_verdicts)
  end

  defp stale_verdicts(_state, _part, false = _trust_held?), do: []

  defp overtaken?(_told_seq, nil), do: false

  defp overtaken?(nil, _overtaking_seq), do: true

  defp overtaken?(told_seq, overtaking_seq), do: overtaking_seq > told_seq

  # Whether what the session holds can be trusted to say what the client holds of the batch's rows.
  # Not for a batch with a transaction below the edge read once the fill or the catch-up was over.
  # The fill read each type at its own moment, so such a transaction can be in the rows of some
  # types and not in those read before it committed - a row it made readable was sent with the type
  # read after it, while the rows read before named nothing of it. A catch-up takes its client to
  # hold what the user may read when it reads that, which a transaction committing around it can
  # make true of a row the client never got, and its chunks read the rows after that. Such a batch
  # hands every row it may read over whole, which restates its sets and tells the pairs filed under
  # the rows read before (see `Hologram.Sync.Pot.decide/3`).
  defp trusts_held?(%{trust_edge: nil}, _part), do: true

  defp trusts_held?(%{trust_edge: trust_edge}, %{tx_range: {lowest, _highest}}) do
    lowest >= trust_edge
  end

  defp max_place(nil, place), do: place

  defp max_place(place, other_place), do: max(place, other_place)
end
