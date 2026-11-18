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
  # A client coming back with a place is caught up through the windows first: it is subscribed to
  # every window this build downloads, and keeps each window's last version and what moved in and
  # out of it while it is caught up. What it keeps of them is ids, never rows - the rows live once
  # per node in the result store - bar the hidden rows that left a window, bounded by what moved
  # meanwhile, and the rows the gap names that no window carries, bounded by the gap.
  # It joins the node's sessions before it takes up a window, and before the gap is read it reads
  # what its user may read, which it takes the client to hold once caught up; then it leaves the
  # windows and is synced by read access like a first arrival.

  use GenServer, restart: :temporary

  alias Hologram.Auth
  alias Hologram.DB.Codec
  alias Hologram.DB.Oplog
  alias Hologram.DB.QueryCache
  alias Hologram.Entity
  alias Hologram.Policy
  alias Hologram.Query.Registry
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Diff
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Fill
  alias Hologram.Sync.Frame
  alias Hologram.Sync.Held
  alias Hologram.Sync.Live
  alias Hologram.Sync.PackedIds
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.Pot
  alias Hologram.Sync.ResultStore
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
  `Hologram.Sync.Cursor.types_hash/1`), taken where the session is started and stamped on every
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
  effects since the client's place and the grants it held there, or why it has to be sent
  everything again, which ends the session with `{:full_resync, reason}` so the client comes back
  through the doors. Given one, the client keeps what it already holds and is told only about the
  rows the gap names. Handed over as a reader rather than as the effects, because the log is read
  only once every window has filled - a change committed while they fill is then in the gap rather
  than lost between the rounds a catching-up session passes over - and the read runs in this
  process. Whether a gap can be had at all is decided before the session starts, since it is a
  question about the log rather than about this client - the session's own read finding it can't
  is the log having moved since, a gap that outgrew a replay or a deploy landing in between.

  `:read_fill` reads what a client arriving with nothing is sent of one entity type, answering what
  `Hologram.Sync.Fill.read/4` answers, which it defaults to. Handed over as a reader for the same
  reason `:read_gap` is: the read runs in this process, and what it runs in is the caller's to say.

  `:read_named` reads, for a returning client, the rows the gap names that no window carries,
  answering what `Hologram.Sync.Fill.read_named/4` answers, which it defaults to - a reader for the
  same reason.

  `:read_ids` reads, for a returning client, the ids of the rows of one entity type its user may
  read, packed, answering what `Hologram.Sync.Fill.read_ids/2` answers, which it defaults to - a
  reader for the same reason.

  `:gap_end` is the place of the last effect the read that decided this client resumes found, or
  nil when it found none. A catch-up frame names no place past it: the session's own read can
  name effects whose rounds have not reached it yet, and a frame dating those would let a client
  cut off right then come back past changes it never held.

  `:edges` is the policy dependency index, given to a returning client alone - what each rule
  reads besides the row it judges, so a row the gap never names can be judged again when the row
  DECIDING it moved. A rule saying `via:` reads a related row, and that row going private hides
  everything leaning on it without any of them moving. Absent for a first arrival, which is sent
  every row it may see.

  Windows that nothing downloads are skipped rather than refused, which is how a client naming a
  page this build does not have still gets the rest of the build's windows.
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

    state = %{
      actor_user_id: Keyword.get(opts, :actor_user_id),
      announced: MapSet.new(),
      applied_seq: Keyword.get(opts, :applied_seq),
      arrived: MapSet.new(),
      catching_up: read_gap != nil,
      client: Keyword.fetch!(opts, :client),
      client_ref: nil,
      cut: nil,
      departed: %{},
      edges: Keyword.get(opts, :edges),
      fill_place: Keyword.get(opts, :fill_place),
      gap_end: Keyword.get(opts, :gap_end),
      # A client arriving with nothing is synced by read access from the start; a returning one is
      # caught up through the windows first, and then leaves them.
      live?: read_gap == nil,
      page: Keyword.fetch!(opts, :page),
      page_types: MapSet.new(),
      page_windows: MapSet.new(),
      pending: MapSet.new(),
      place: Keyword.get(opts, :fill_place),
      policy_hash: Keyword.fetch!(opts, :policy_hash),
      pot: Pot.new(),
      queued_parts: [],
      read_fill: Keyword.get(opts, :read_fill, &Fill.read/4),
      read_gap: read_gap,
      read_ids: Keyword.get(opts, :read_ids, &Fill.read_ids/2),
      read_named: Keyword.get(opts, :read_named, &Fill.read_named/4),
      replica_id: Keyword.get(opts, :replica_id),
      resuming: read_gap != nil,
      synced_labels: %{},
      told_verdicts: %{},
      trust_edge: nil,
      types_hash: Keyword.fetch!(opts, :types_hash),
      unsent: nil,
      versions: %{},
      window_refs: %{}
    }

    # Watched as well as linked: a link takes this session down only with a client that crashes,
    # and one that ends normally would leave it among the node's sessions, judged for and sent every
    # batch for nobody.
    {:ok, %{state | client_ref: Process.monitor(state.client)}, {:continue, :subscribe}}
  end

  # A client arriving with nothing joins the sessions every batch is judged for before anything is
  # read, so every batch read after it reaches this session, and the fill - read after it - holds
  # everything committed before. It takes up no window.
  @impl GenServer
  def handle_continue(:subscribe, %{live?: true} = state) do
    :ok = Sessions.register(state.actor_user_id)

    {:noreply, fill(%{state | page_types: page_types(state.page)})}
  end

  # A returning client joins them before it takes up any window, for the same reason: a batch read
  # after that reaches it as a part, kept until it is caught up, and one read before had its rounds
  # handed to every evaluator before the session asked to join them - so the round a window first
  # tells the session holds it.
  def handle_continue(:subscribe, state) do
    :ok = Sessions.register(state.actor_user_id)

    page_window_ids = PageWindows.lookup(state.page)
    background_window_ids = PageWindows.all() -- page_window_ids
    window_ids = page_window_ids ++ background_window_ids

    # Every window counts as outstanding before any of them is taken up, so one that fills while
    # the others are still being taken up cannot empty the set and say the client has everything.
    seeded = %{
      state
      | page_windows: MapSet.new(page_window_ids),
        pending: MapSet.new(window_ids)
    }

    # A client with nothing to wait for is told so at once: one left waiting for a marker that
    # never comes would never read its own store.
    subscribed = Enum.reduce(window_ids, announce(seeded), &subscribe_to_window/2)

    after_catching_up(state, subscribed)
  end

  # What the process reports of itself - to `:sys.get_status/1`, and in the report a crash or a
  # cut writes - leaves out what it holds of rows this client may not read: the rows that left a
  # window hidden from it while it was being caught up (see `departure/2`), each named by its type
  # alone, the batches it keeps meanwhile, counted, and the values the round or batch it was
  # reading carried, which are every client's. A log is no place for any of them.
  @impl GenServer
  def format_status(status) do
    status
    |> Map.update(:state, nil, fn state ->
      %{
        state
        | departed: Map.new(state.departed, &redact_departure/1),
          queued_parts: length(state.queued_parts)
      }
    end)
    |> redact_message()
  end

  defp redact_message(%{message: {:round, window_id, version, _transactions, place}} = status) do
    %{status | message: {:round, window_id, version, :redacted, place}}
  end

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

  # A part reaching a client still being caught up waits for the catch-up, which tells the kept
  # parts in the order they came once the client is caught up.
  def handle_info({:live, part}, %{catching_up: true} = state) do
    {:noreply, %{state | queued_parts: [part | state.queued_parts]}}
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

  def handle_info({:DOWN, ref, :process, _client, _reason}, %{client_ref: ref} = state) do
    {:stop, :normal, state}
  end

  # An evaluator this session was reading has stopped, and nothing else will arrive for its window
  # - the same cliff as a round falling out of the ring, and taken the same way. Cut rather than
  # repaired in place: what stopped it is not known here, and the reason that matters most - the
  # whole sync unit going down with the database - takes the registry and the stored rows too, so
  # there is nothing left to rejoin. The client comes back through the doors instead, where its
  # model, its place and the size of its gap are all read again rather than assumed.
  def handle_info({:DOWN, _ref, :process, _evaluator, _reason}, state) do
    {:stop, :evaluator_gone, state}
  end

  # A session on its way out reads no more rounds, the ones still queued ahead of the cut message
  # included: the client comes back through the doors, and is caught up there.
  def handle_info({:round, _window_id, _version, _transactions, _place}, %{cut: cut} = state)
      when cut != nil do
    {:noreply, state}
  end

  # Rounds still queued once the session has left its windows tell nothing: the client is synced
  # by read access from then on. One an evaluator sent before it read the unsubscribe can carry
  # big values, so the session sleeps after it as after a part.
  def handle_info({:round, _window_id, _version, _transactions, _place}, %{live?: true} = state) do
    noreply_sleeping_when_idle(state)
  end

  # The rounds of a client being caught up tell nothing: they keep what entered and left each
  # window, which the catch-up judges against once every window has had its first.
  def handle_info({:round, window_id, version, transactions, _place}, state) do
    events = Enum.flat_map(transactions, fn {_tx, events} -> events end)

    after_catching_up(state, deliver(remember_applied(state, events), window_id, version))
  end

  # The callback that catches the client up hibernates the session after it: what the catch-up
  # read and judged, and the batches it kept, are garbage by then, and a session can sit idle for
  # as long as its client stays, with nothing allocating to collect them.
  defp after_catching_up(%{catching_up: true}, %{catching_up: false} = state) do
    {:noreply, state, :hibernate}
  end

  defp after_catching_up(_before, state), do: {:noreply, state}

  # A part's packed ids are shared with every session it went to, and a session holds onto them
  # until it next collects its garbage - which an idle one never does. So one with nothing else to
  # read sleeps, collecting as it goes.
  defp noreply_sleeping_when_idle(state) do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, 0} -> {:noreply, state, :hibernate}
      _more_to_read -> {:noreply, state}
    end
  end

  # A cut met while the windows are still being taken up leaves the rest of them to be subscribed
  # to, and nothing of theirs is told either.
  defp deliver(%{cut: cut} = state, _window_id, _version) when cut != nil do
    state
  end

  defp deliver(state, window_id, version) do
    case ResultStore.fetch(window_id, version) do
      # The round fell out of the ring before this session read it, so this client is further
      # behind than the store reaches - the same cliff as coming back to a log that no longer
      # covers you, and answered the same way: the connection is cut and the client comes back
      # through the doors like any returning one. Cutting is what the session HAS to do rather
      # than filling again in place, because what it holds is what the client was told, and a
      # round it cannot read leaves it unable to say what that still is.
      nil ->
        cut(state, :behind_the_ring)

      result ->
        state
        |> remember_moved(window_id, result)
        |> remember_version(window_id, version)
        |> mark_filled(window_id)
    end
  end

  # A client being caught up is told nothing until it is: what it holds is stale until the gap
  # lands, and a marker saying otherwise would have it read a store that lies. Once every window
  # has reported, what the client may see is known, and the gap can be read and spoken.
  #
  # A session on its way out says nothing more: the client comes back through the doors, and
  # anything told in between is told again there.
  defp announce(%{cut: nil} = state) do
    if Enum.empty?(state.pending), do: catch_up(state), else: state
  end

  defp announce(state), do: state

  # The marker carries the place, and the place is computed from the state that ALREADY records
  # the pot as announced - `cursor/1` answers nil until the client holds a whole pot, and
  # announcing `:all` is precisely what makes that true. Computed from `state` instead, the frame
  # that says "you have everything" would be the one frame unable to say where everything ends.
  defp announce_all(state) do
    if Enum.empty?(state.pending) and not MapSet.member?(state.announced, :all) do
      announced = %{state | announced: MapSet.put(state.announced, :all)}

      send(announced.client, {:sync_synced, :all, cursor(announced)})

      announced
    else
      state
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

    {filled, named} =
      Enum.reduce(fill_order, {state, %{}}, fn entity_type, {acc, named} ->
        fill_type(acc, named, entity_type, synced_types)
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
      |> Enum.reduce(%{state | applied_seq: applied_seq}, fn chunk, acc ->
        deltas = Enum.map(chunk, &Frame.put_entity(&1, Frame.row_verdicts(acc.actor_user_id, &1)))

        send(acc.client, {:sync_deltas, nil, deltas, applied_seq})

        remember_verdicts(acc, deltas)
      end)

    send(told.client, {:sync_synced, {:types, [entity_type]}, nil})

    pot = Pot.hand_over(told.pot, entity_type, Enum.map(rows, & &1.id))

    {%{told | pot: pot}, name_set_members(rows, named)}
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

  # The gap is read only now, once every window has filled, rather than when the session began.
  # Rounds reaching a session that is catching up tell nothing, so a change committed while the
  # windows were filling would otherwise be told by nobody: its round is passed over, and a window
  # filling after it reads it as a row that was always so. Read now, the gap names everything
  # committed before this moment, and the batches after it reach the session as parts, told once
  # the client is caught up.
  #
  # Two answers end the session instead: a log that can no longer tell this client what it
  # missed, and a window whose last round left the ring before the gap could be judged against it.
  #
  # The session joined the node's sessions before it took up a window, so every batch since
  # reaches it, kept until now, and the gap, read after that, covers the ones before. Before the
  # gap it reads what its user may read now, which it takes the client to hold once caught up -
  # read first, so a row its user loses is either in the gap, which names it, or in a batch after
  # the read, which finds it held and takes it away. Each frame of the catch-up moves what it
  # holds, and once the client is caught up the session leaves its windows, is synced by read
  # access, and tells the batches it kept.
  defp catch_up(state) do
    held = read_held(state)

    case held.read_gap.() do
      {:ok, gap, grants_then} ->
        case judge_gap(held, gap, grants_then) do
          {:ok, judged} ->
            held
            |> tell_gap(judged)
            |> leave_windows()
            |> announce_all()
            |> tell_queued_parts()

          :behind_the_ring ->
            cut(held, :behind_the_ring)
        end

      {:full_resync, reason} ->
        cut(held, {:full_resync, reason})
    end
  end

  # The labels are kept for the catch-up's frames, each of which names its rows' types by label
  # (see `remember_held/2`).
  defp read_held(state) do
    synced_types = QueryCache.synced_types()

    held =
      Enum.reduce(synced_types, Held.new(), fn entity_type, acc ->
        Held.put(acc, entity_type, state.read_ids.(entity_type, state.actor_user_id))
      end)

    %{
      state
      | pot: Pot.from_held(held),
        synced_labels: Map.new(synced_types, &{Codec.encode_enum_value(&1), &1})
    }
  end

  # The batches that reached the session while its client was caught up, in the order they came -
  # each decided against the edge read once the catch-up was over (see `trusts_held?/2`).
  defp tell_queued_parts(state) do
    state.queued_parts
    |> Enum.reverse()
    |> Enum.reduce(%{state | queued_parts: []}, &tell_part(&2, &1))
  rescue
    Hologram.StaleModelError -> cut(state, {:shutdown, :model_held})
  end

  # Once the client is caught up its windows have nothing more to tell it, so the session leaves
  # them - an evaluator nobody else holds stops - and is synced by read access. A frame claims the
  # place the session started from until a batch moves it: the gap covers everything before it.
  defp leave_windows(state) do
    Enum.each(state.window_refs, fn {window_id, ref} ->
      Evaluator.unsubscribe(window_id, self())
      Process.demonitor(ref, [:flush])
    end)

    %{
      state
      | edges: nil,
        live?: true,
        pending: MapSet.new(),
        place: state.fill_place,
        synced_labels: %{},
        trust_edge: Oplog.current_xmax(),
        window_refs: %{}
    }
  end

  # The session ends once what is already queued ahead of the message has been read, so every
  # caller of this can carry on returning state.
  defp cut(state, reason) do
    send(self(), {:cut, reason})

    %{state | cut: reason}
  end

  # Judged against each window's last round, one window's rows read at a time: which of them the
  # gap named or entered a window during the catch-up (`touched`), which a grant change or a moved
  # related row decided differently (`shift`), the ones whose verdicts the client may hold
  # (`verdict_rows`), and whether the client may see each row a window carries (`visibility`),
  # beside the gap and the grants it held before it went away. Nothing of it outlives the catch-up,
  # so it is a value the frames are told from, never part of the session.
  #
  # The windows' last rounds were read at different moments, so two copies of one row can differ:
  # a window whose round for a change is still queued has the row as it was. So the windows are
  # judged in the order their rounds were read and a later copy wins, holding every write an
  # earlier one does - its values and the sets it includes alike. What the client may see of a row
  # is decided the same way, by the last window carrying it, and only once every window is judged
  # is anything filtered by it: a row hidden by then is taken away rather than handed over, and the
  # lists of the rows handed over name exactly what the client may see then, whatever an earlier
  # window let it see. Judged in any other order, the older copy could win, and the round that
  # would correct it was already passed over while the client was catching up. Nothing on the row
  # itself can stand in for that order: a column's revision moves only when that column is
  # written, and a pair moves none.
  #
  # The order is when each query was asked for, not when the database took its snapshot: two
  # windows' queries waiting on the pool can be answered in the other order, and a write landing
  # between those two snapshots is then held by the copy that loses.
  defp judge_gap(state, gap, grants_then) do
    named_ids =
      gap
      |> Enum.flat_map(&gap_ids/1)
      |> MapSet.new()

    unjudged = %{
      gap: gap,
      grants_then: grants_then,
      reread_ids: MapSet.new(),
      shift: %{appeared: %{}, vanished: %{}},
      touched: %{},
      verdict_rows: %{},
      visibility: %{}
    }

    # A row that entered a window while the client was being caught up is kept as a named one is,
    # to be handed over as it stands once every window is judged.
    kept_ids = MapSet.union(named_ids, state.arrived)

    with {:ok, ordered} <- read_order(state.versions) do
      Enum.reduce_while(ordered, {:ok, unjudged}, fn {window_id, version}, {:ok, acc} ->
        judge_next(acc, state, window_id, version, grants_then, kept_ids)
      end)
    end
  end

  defp judge_next(judged, state, window_id, version, grants_then, kept_ids) do
    case ResultStore.fetch(window_id, version) do
      nil -> {:halt, :behind_the_ring}
      result -> {:cont, {:ok, judge_window(judged, state, result, grants_then, kept_ids)}}
    end
  end

  # The windows' last rounds, earliest read first. A round gone from the ring already is the same
  # cliff here as when its rows are read.
  defp read_order(versions) do
    read_ats =
      Enum.map(versions, fn {window_id, version} ->
        {ResultStore.read_at(window_id, version), window_id, version}
      end)

    if Enum.any?(read_ats, fn {read_at, _window_id, _version} -> is_nil(read_at) end) do
      :behind_the_ring
    else
      ordered =
        read_ats
        |> Enum.sort()
        |> Enum.map(fn {_read_at, window_id, version} -> {window_id, version} end)

      {:ok, ordered}
    end
  end

  # The rows are kept as the window carries them, embedded lists whole: what the client may see of
  # those lists is known only once the windows read after this one have been judged too.
  defp judge_window(judged, state, result, grants_then, kept_ids) do
    {members, visible_ids} = Diff.carried(result, state.actor_user_id)

    judged
    |> remember_visibility(members, visible_ids)
    |> remember_touched(members, visible_ids, kept_ids)
    |> remember_verdict_rows(members, visible_ids)
    |> remember_shift(state, result, members, grants_then)
    |> remember_reach(state, result, members)
  end

  # What the client may see as of the last window carrying each row, which every frame is filtered
  # by. Ids alone, for every row a window carries - a row's lists can name any of them.
  defp remember_visibility(judged, members, visible_ids) do
    judgments = Map.new(members, fn {id, _row} -> {id, MapSet.member?(visible_ids, id)} end)

    %{judged | visibility: Map.merge(judged.visibility, judgments)}
  end

  # Only what the client may see as of the last window judged goes out, with every list it embeds
  # holding only what the client may see too. A row that left the client's sight by then is no row
  # to hand over, and one shown again is no row to take away.
  defp settle(judged) do
    visible_ids =
      judged.visibility
      |> Enum.filter(fn {_id, visible?} -> visible? end)
      |> MapSet.new(fn {id, _visible?} -> id end)

    vanished =
      Map.reject(judged.shift.vanished, fn {id, _row} -> MapSet.member?(visible_ids, id) end)

    %{
      judged
      | shift: %{appeared: visible_only(judged.shift.appeared, visible_ids), vanished: vanished},
        touched: visible_only(judged.touched, visible_ids),
        # Not scrubbed: only their verdicts are told, and the verdicts read the sets they quantify
        # over from the database, never from what the row embeds.
        verdict_rows:
          Map.filter(judged.verdict_rows, fn {id, _row} -> MapSet.member?(visible_ids, id) end)
    }
  end

  # The rows that go out whole, with every list they embed holding only what the client may see.
  defp visible_only(rows, visible_ids) do
    rows
    |> Map.filter(fn {id, _row} -> MapSet.member?(visible_ids, id) end)
    |> Map.new(fn {id, row} -> {id, Diff.scrub(row, visible_ids)} end)
  end

  # What the client missed, told from the rows as they stand now rather than from the log's own
  # account of them. Everything it holds that the gap never touched is still true, and is left
  # alone - which is the whole saving over sending it the lot.
  defp tell_gap(state, unsettled) do
    {judged, reread_seq} =
      unsettled
      |> settle()
      |> reread_unseen(state)

    # The rows read again carry what this replica's batches had done by the time they were read,
    # which can be past what the gap's own effects say.
    state = %{state | applied_seq: higher_seq(state.applied_seq, reread_seq)}

    # The watermark is raised by every one of this replica's effects in the gap before any frame
    # goes out, wherever the deciding read ended. Every row goes out as it stands, so an early frame
    # can carry a row with a write of this replica's that only a later frame names - and a row going
    # out with the write in it under a number saying it isn't has the client apply the write a
    # second time. A window's round can be older than one of these writes, and the client then
    # shows the row from before its write until the batch holding it is told.
    told_moved =
      state
      |> remember_applied(judged.gap)
      |> tell_moved(judged)

    caught_up =
      judged.gap
      |> Enum.chunk_every(Catchup.rows_per_frame())
      |> Enum.reduce(told_moved, &tell_batch(&2, judged, &1))
      |> tell_shift(judged)
      |> tell_verdicts(judged)

    %{
      caught_up
      | arrived: MapSet.new(),
        catching_up: false,
        departed: %{},
        read_gap: nil,
        versions: %{}
    }
  end

  # What moved in or out of the windows while the client was being caught up, through nothing the gap
  # names: the rows that entered a window are handed over (see `arrived_puts/2`), and the ones that
  # left are taken away. A row that left a window, and that no window's last round lets the client
  # see, has left every window. Only a row the client may hold is taken away: one it could see in
  # the round it left, or a hidden one it could see before it went away, under the grants it held
  # then or before a related row the gap names moved - which, like the reach of the rows a last
  # round carries, errs towards taking away. So does a row that entered a window during the catch-up
  # and left again: it can't be told apart from one another window held from its first round, and
  # taking away a row the client never had changes nothing. Rows the gap names or the shift takes
  # away are spoken for there.
  #
  # Told first and dated by nothing: the batches after it each claim a place, and a client cut off
  # after the last of them comes back with nothing left to replay, its windows already holding the
  # rows that entered and no round carrying the ones that left. Handing over or taking away a row
  # twice changes nothing.
  defp tell_moved(state, judged) do
    vanished_ids =
      judged.shift.vanished
      |> Map.keys()
      |> MapSet.new()

    told_ids =
      judged.gap
      |> MapSet.new(& &1.entity_id)
      |> MapSet.union(vanished_ids)
      |> MapSet.union(judged.reread_ids)

    {visible, hidden} =
      state.departed
      |> Enum.reject(fn {id, _departure} ->
        Map.get(judged.visibility, id, false) or MapSet.member?(told_ids, id)
      end)
      |> Enum.split_with(fn {_id, departure} -> match?({:visible, _type}, departure) end)

    held_hidden = held_hidden(hidden, state, judged)

    # A row that left every window is not one its user may no longer read: the session read what
    # it may read before the gap, and a row among that stays.
    unsyncs =
      visible
      |> Enum.map(fn {id, {:visible, type}} -> {id, type} end)
      |> Enum.concat(held_hidden)
      |> Enum.reject(fn {id, type} -> Held.member?(state.pot.held, type, id) end)
      |> Enum.sort()
      |> Enum.map(fn {id, type} -> Frame.unsync_entity(id, type) end)

    state
    |> arrived_puts(judged)
    |> Enum.concat(unsyncs)
    |> Enum.chunk_every(Catchup.rows_per_frame())
    |> Enum.reduce(state, fn deltas, acc ->
      send(acc.client, {:sync_deltas, nil, deltas, acc.applied_seq})

      acc
      |> remember_verdicts(deltas)
      |> remember_held(deltas)
    end)
  end

  # A row that entered a window while the client was being caught up, through nothing the gap
  # names - a related row moving into a window's filter brings rows that never changed - and that
  # the client may see once every window is judged, is handed over as it stands. Rows the gap names
  # or the shift hands over are spoken for there.
  defp arrived_puts(state, judged) do
    named_ids = MapSet.new(judged.gap, & &1.entity_id)

    state.arrived
    |> Enum.reject(&(MapSet.member?(named_ids, &1) or Map.has_key?(judged.shift.appeared, &1)))
    |> Enum.sort()
    |> Enum.flat_map(fn id ->
      case Map.fetch(judged.touched, id) do
        {:ok, row} -> [Frame.put_entity(row, Frame.row_verdicts(state.actor_user_id, row))]
        :error -> []
      end
    end)
  end

  # The hidden rows that left a window which the client could see before it went away - under the
  # grants it held then, or before a row the gap names moved and hid them through a rule leaning on
  # it.
  defp held_hidden(hidden, state, judged) do
    rows = Map.new(hidden, fn {id, {:hidden, row}} -> {id, row} end)

    by_grants =
      if judged.grants_then do
        rows
        |> Map.filter(fn {_id, row} ->
          Auth.can?(state.actor_user_id, :read, row, judged.grants_then)
        end)
        |> Map.keys()
      else
        []
      end

    by_reach =
      if state.edges do
        ids =
          rows
          |> Map.keys()
          |> MapSet.new()

        %{ids: ids, rows: rows}
        |> Diff.reach(state.actor_user_id, judged.gap, state.edges)
        |> Map.fetch!(:vanished)
        |> Enum.map(& &1.id)
        # The reach judges the rows embedded under these too - only the departed ones are asked
        # about here.
        |> Enum.filter(&Map.has_key?(rows, &1))
      else
        []
      end

    by_grants
    |> Enum.concat(by_reach)
    |> Enum.uniq()
    |> Enum.map(&{&1, Map.fetch!(rows, &1).__struct__})
  end

  # What a grant change decided differently, told after the rows the gap named and before the
  # client is told its store is answerable. A row the gap named is left out: the replay has
  # already handed it over as it stands, or already taken it away, and saying so twice would
  # have the client apply an answer to a question it was given the answer to. The target of an
  # edge the replay handed over beside it can be put again here - the same row as it now stands,
  # which a second put leaves as it was.
  defp tell_shift(state, judged) do
    named = MapSet.new(judged.gap, & &1.entity_id)

    puts =
      judged.shift.appeared
      |> shift_rows(named)
      |> Enum.map(&Frame.put_entity(&1, Frame.row_verdicts(state.actor_user_id, &1)))

    unsyncs =
      judged.shift.vanished
      |> shift_rows(named)
      |> Enum.map(&Frame.unsync_entity(&1.id, &1.__struct__))

    puts
    |> Enum.concat(unsyncs)
    |> Enum.chunk_every(Catchup.rows_per_frame())
    |> Enum.reduce(state, fn deltas, acc ->
      send(acc.client, {:sync_deltas, batch_cursor(acc, judged.gap), deltas, acc.applied_seq})

      acc
      |> remember_verdicts(deltas)
      |> remember_held(deltas)
    end)
  end

  # A returning client holds verdicts it was told before this session began, on rows the gap may
  # never name. A gap under other rules never gets here - it is sent everything again - but two
  # things can still leave those verdicts stale with nothing in the gap saying so: a client cut off
  # after the last batch of an earlier catch-up, before its verdicts went out, comes back with an
  # empty gap, and a deploy that starts checking permissions in the browser changes no rule while
  # the rows it was sent carry no verdicts at all. So every row of a type with a deciding quantifier
  # that the catch-up did not already hand over with its verdicts is told them, after the rows
  # themselves.
  defp tell_verdicts(state, judged) do
    judged.verdict_rows
    |> Map.drop(Map.keys(state.told_verdicts))
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Verdicts.stale(state.told_verdicts, state.actor_user_id)
    |> Enum.map(fn {row, verdicts} -> {row, %{}, verdicts} end)
    |> Enum.chunk_every(Catchup.rows_per_frame())
    |> Enum.reduce(state, fn patched, acc ->
      news = %{appeared: [], edges: [], patched: patched, unsynced: []}
      deltas = Frame.deltas(news, acc.actor_user_id)

      send(acc.client, {:sync_deltas, batch_cursor(acc, judged.gap), deltas, acc.applied_seq})

      remember_verdicts(acc, deltas)
    end)
  end

  defp shift_rows(rows, named) do
    rows
    |> Map.reject(fn {id, _row} -> MapSet.member?(named, id) end)
    |> Map.values()
  end

  # Judged per window, merged by id: visibility is per ROW and per client rather than per window,
  # so a later window's judgment of a row supersedes an earlier one's. What appeared is kept as the
  # window carries it, for its lists to be scrubbed once every window is judged.
  #
  # Two sources feed the one accumulator, and they answer different questions about the same
  # rows: what the client's GRANTS moving decided differently, and what a row the gap names now
  # decides about the rows leaning on it. Both end up in the batch `tell_shift/2` sends.
  defp merge_shift(judged, shift, members) do
    appeared_ids = Enum.map(shift.appeared, & &1.id)

    appeared = merge_later(judged.shift.appeared, Map.take(members, appeared_ids))
    vanished = Map.merge(judged.shift.vanished, Map.new(shift.vanished, &{&1.id, &1}))

    %{judged | shift: %{appeared: appeared, vanished: vanished}}
  end

  # Only for a client that was handed a dependency index - a first arrival has nothing to reach
  # back for.
  defp remember_reach(judged, %{edges: nil}, _result, _members), do: judged

  defp remember_reach(judged, state, result, members) do
    shift = Diff.reach(result, state.actor_user_id, judged.gap, state.edges)

    merge_shift(judged, shift, members)
  end

  # Only when the gap came back with grants to judge against.
  defp remember_shift(judged, _state, _result, _members, nil), do: judged

  defp remember_shift(judged, state, result, members, grants_then) do
    merge_shift(judged, Diff.shift(result, state.actor_user_id, grants_then), members)
  end

  # Each batch claims ITS OWN last place rather than the whole gap's, which is what makes a replay
  # resumable: a client cut off after three of ten batches comes back dated to the third and is
  # given the rest, instead of starting the gap again. The batches are read in log order, so the
  # place of a batch's last effect is a place everything before it has been applied to.
  defp tell_batch(state, judged, effects) do
    deltas = Catchup.deltas(effects, judged.touched, state.actor_user_id)

    if deltas != [] do
      send(state.client, {:sync_deltas, batch_cursor(state, effects), deltas, state.applied_seq})
    end

    state
    |> remember_verdicts(deltas)
    |> remember_held(deltas)
  end

  # A gap of nothing dates nothing - the client keeps the place it came back from, as a frame
  # mid-fill leaves it. Neither does a gap the deciding read found empty: what this session read
  # since is past every place a frame may vouch for (see `:gap_end`).
  defp batch_cursor(_state, []), do: nil

  defp batch_cursor(%{gap_end: nil}, _effects), do: nil

  defp batch_cursor(state, effects) do
    if holds_a_whole_pot?(state) do
      %{seq: seq, tx: tx} = List.last(effects)
      {capped_tx, capped_seq} = min({tx, seq}, state.gap_end)

      Cursor.encode(capped_tx, capped_seq, state.policy_hash, state.types_hash)
    end
  end

  defp mark_filled(state, window_id) do
    filled = %{state | pending: MapSet.delete(state.pending, window_id)}

    announce(filled)
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

  # How far this replica's own batches are applied in what the client is about to be told, taken
  # from the effects themselves: every one of them names the batch that wrote it, and the highest
  # number among this replica's is one the frame's values are known to include.
  #
  # Taken FORWARD only. A round carrying none of this replica's writes says nothing about them,
  # which is not the same as saying they are gone - and the client reads this as "everything up to
  # here of mine is in", so a number that fell would have it apply landed writes a second time.
  defp remember_applied(state, events) do
    highest =
      events
      |> Enum.filter(&own_batch?(state, &1))
      |> Enum.map(& &1.mutation_ref["seq"])
      |> Enum.max(fn -> nil end)

    %{state | applied_seq: higher_seq(state.applied_seq, highest)}
  end

  # Whether an effect is one this replica's own writes caused. An effect with no batch behind it -
  # a command's write, a seed's, the framework's own - belongs to nobody, and a session serving no
  # replica owns nothing at all.
  defp own_batch?(%{replica_id: nil}, _event), do: false

  defp own_batch?(state, %{mutation_ref: %{"replica_id" => replica_id}}) do
    replica_id == state.replica_id
  end

  defp own_batch?(_state, _event), do: false

  # Nil is "no number", never zero: a replica that has had nothing applied and one this stream
  # cannot name are both spoken of by saying nothing.
  defp higher_seq(nil, seq), do: seq

  defp higher_seq(seq, nil), do: seq

  defp higher_seq(left, right), do: max(left, right)

  # What each window's last round was, read at its next round and when the gap is judged.
  defp remember_version(%{catching_up: true} = state, window_id, version) do
    %{state | versions: Map.put(state.versions, window_id, version)}
  end

  defp redact_departure({id, {:hidden, row}}), do: {id, {:hidden, row.__struct__}}

  defp redact_departure(departure), do: departure

  # A row the client could see when it left is kept as its type alone, all its unsync needs. A
  # hidden one is kept whole, to be judged against what the client could see before it went away.
  defp departure(row, actor_user_id) do
    if Auth.can?(actor_user_id, :read, row) do
      {:visible, row.__struct__}
    else
      {:hidden, row}
    end
  end

  # The rows a window's round no longer carries that its previous round during the catch-up did - a
  # parent turned private takes the rows embedded under it along - and the rows it carries that the
  # previous round didn't. The catch-up judges each window's last round only, so a row that left
  # before it is in no round the catch-up sees, and is kept here (see `departure/2`) until the
  # catch-up decides whether it has left every window. A row coming back is no longer one that left,
  # and neither is it one that arrived, since the client may still hold it. One that arrived stays
  # so, wherever it goes after: whether it goes out is decided by the windows' last rounds. Bounded
  # by what moved while the client was being caught up.
  #
  # The previous round is read back from the store, and one already gone cuts the client off the
  # way a round that can't be read does - a round sooner than before, since both have to still be
  # there.
  defp remember_moved(%{catching_up: true} = state, window_id, result) do
    case Map.fetch(state.versions, window_id) do
      {:ok, previous_version} -> remember_moved(state, window_id, result, previous_version)
      :error -> state
    end
  end

  defp remember_moved(state, window_id, result, previous_version) do
    case ResultStore.fetch(window_id, previous_version) do
      nil ->
        cut(state, :behind_the_ring)

      previous ->
        carried_ids =
          result
          |> Diff.carried_rows()
          |> Map.keys()

        previous_rows = Diff.carried_rows(previous)

        left =
          previous_rows
          |> Map.drop(carried_ids)
          |> Map.new(fn {id, row} -> {id, departure(row, state.actor_user_id)} end)

        departed =
          state.departed
          |> Map.drop(carried_ids)
          |> Map.merge(left)

        # A row coming back after it left during the catch-up is one the client may still hold,
        # so it is neither one that left nor one that arrived.
        entered =
          Enum.reject(carried_ids, fn id ->
            Map.has_key?(previous_rows, id) or Map.has_key?(state.departed, id)
          end)

        arrived = MapSet.union(state.arrived, MapSet.new(entered))

        %{state | arrived: arrived, departed: departed}
    end
  end

  # What a catch-up frame hands over or takes away moves what the session takes the client to hold.
  # A delta names its type as the wire spells it, so the label is read back as the synced type it
  # names. A row of a type sync doesn't send is no row live sync tells of, so it is passed over.
  #
  # Moved once per type per frame rather than once per row: each move copies the type's packed ids.
  # No catch-up frame both hands over and takes away one row, so the order of the two moves can't
  # matter.
  defp remember_held(state, frame_deltas) do
    types = state.synced_labels

    moved =
      frame_deltas
      |> Enum.filter(&(&1.op in [:put_entity, :unsync_entity] and Map.has_key?(types, &1.type)))
      |> Enum.group_by(&{&1.op, Map.fetch!(types, &1.type)}, & &1.id)

    pot =
      Enum.reduce(moved, state.pot, fn
        {{:put_entity, entity_type}, ids}, acc -> Pot.hand_over(acc, entity_type, ids)
        {{:unsync_entity, entity_type}, ids}, acc -> Pot.drop(acc, entity_type, ids)
      end)

    %{state | pot: pot}
  end

  # What a frame told of the server's verdicts, kept so a later batch tells only what moved.
  defp remember_verdicts(state, frame_deltas) do
    %{state | told_verdicts: Verdicts.remember(state.told_verdicts, frame_deltas)}
  end

  # The rows the client may see whose type has a deciding quantifier, from every window, so the
  # verdicts it holds from before this session can be told again once it is caught up. Only the
  # ones this window lets it see: a row hidden here and shown later is taken from the later window,
  # and one shown here and hidden later is dropped once every window is judged.
  defp remember_verdict_rows(judged, members, visible_ids) do
    rows =
      members
      |> Map.take(MapSet.to_list(visible_ids))
      |> Map.filter(fn {_id, row} -> Policy.deciding_quantifiers(row.__struct__) != [] end)

    %{judged | verdict_rows: merge_later(judged.verdict_rows, rows)}
  end

  # A copy from a window read later keeps its own values and takes what the earlier copy included
  # and it did not.
  defp merge_later(rows, later_rows) do
    Map.merge(rows, later_rows, fn _id, earlier, later -> Entity.merge_copies(later, earlier) end)
  end

  # The rows the gap names, or that entered a window during the catch-up, that this window lets the
  # client see, as its last round has them. An edge names its target as well as its source, since
  # the target's inverse of it moves too. Only those rows are kept, so the rows held grow with what
  # moved while the client was away or being caught up - a related row bringing many rows into a
  # window brings them all here. Whether a kept row goes out is decided once every window is judged.
  defp remember_touched(judged, members, visible_ids, kept_ids) do
    kept_visible_ids =
      kept_ids
      |> MapSet.intersection(visible_ids)
      |> MapSet.to_list()

    rows = Map.take(members, kept_visible_ids)

    %{judged | touched: merge_later(judged.touched, rows)}
  end

  # What the gap names that no window's last round carries - a row only the fill sent, or one that
  # left every window while its user may still read it - read as it stands through the read rules,
  # since no window has anything to say about it, with how far this replica's batches are in it.
  # A row a window carries is judged by the windows alone, hidden or not. A named row it finds
  # nothing of is gone or hidden, and the replay takes it away.
  #
  # Read after the windows are settled, so the sets a row read here embeds are not scrubbed against
  # what the windows let the client see: they were read through the read rules, which is what the
  # client holds since its fill - bar the rows the gaps #1602 closes leave it with.
  #
  # Bounded by the gap: an id per effect, and a target per edge whose target files the set.
  defp reread_unseen(judged, state) do
    synced_types = QueryCache.synced_types()
    synced = MapSet.new(synced_types)

    ids_by_type =
      judged.gap
      |> Enum.flat_map(&gap_rows/1)
      |> Enum.uniq()
      |> Enum.reject(fn {id, type} ->
        Map.has_key?(judged.visibility, id) or not MapSet.member?(synced, type)
      end)
      |> Enum.group_by(fn {_id, type} -> type end, fn {id, _type} -> id end)

    if ids_by_type == %{} do
      {judged, nil}
    else
      {rows, read_seq} =
        state.read_named.(ids_by_type, state.actor_user_id, state.replica_id, synced_types)

      # The rows found, which the replay hands over - a row asked for and not found is still one
      # `tell_moved/2` may have to take away.
      reread_ids = MapSet.new(rows, & &1.id)
      touched = Map.merge(judged.touched, Map.new(rows, &{&1.id, &1}))

      {%{judged | reread_ids: reread_ids, touched: touched}, read_seq}
    end
  end

  # The rows an effect names, each with its type: an edge names its target too, when the target's
  # type files the set the edge moved - the one a replay hands the target over for.
  defp gap_rows(%{data: %{"relationship" => name, "target_id" => target_id}, op: op} = effect)
       when op in [:add_relationship, :del_relationship] do
    [{effect.entity_id, effect.type} | edge_target(effect.type, name, target_id)]
  end

  defp gap_rows(effect), do: [{effect.entity_id, effect.type}]

  # Edges are written under the to-many names a type declares, so the target is of the type that
  # to-many points at.
  defp edge_target(entity_type, name, target_id) when is_atom(entity_type) do
    relationship =
      Enum.find(entity_type.__relationships__(), fn {relationship_name, _type, _opts} ->
        Atom.to_string(relationship_name) == name
      end)

    with {_name, [target], _opts} <- relationship,
         [_inverse | _more] <- Entity.inverses_of_to_many(target, entity_type, name) do
      [{target_id, target}]
    else
      _nothing_files_it -> []
    end
  end

  defp edge_target(_unknown_type, _name, _target_id), do: []

  defp gap_ids(%{data: %{"target_id" => target_id}, entity_id: entity_id, op: op})
       when op in [:add_relationship, :del_relationship] do
    [entity_id, target_id]
  end

  defp gap_ids(effect), do: [effect.entity_id]

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

  defp subscribe_to_window(window_id, state) do
    case Evaluators.subscribe(window_id, self()) do
      # Nothing downloads it, so nothing will ever arrive for it - which is as filled as it will
      # ever be, and waiting on it would leave the client waiting forever.
      :no_window ->
        mark_filled(state, window_id)

      {:ok, evaluator, version, term} ->
        # Watched from here on: an evaluator that stops is the end of a window's rounds, and a
        # session not told would hold that window pending for as long as the client stayed - never
        # filling or catching it up, never sending a marker, with nothing the client could do about
        # it.
        ref = Process.monitor(evaluator)

        %{state | window_refs: Map.put(state.window_refs, window_id, ref)}
        |> remember_page_types(window_id, term)
        |> first_round(window_id, version)
    end
  end

  # The types a page window reads, which the fill sends first. Taken from the term the subscription
  # handed back rather than read from the cache again: a live reload can drop the window between
  # two reads.
  defp remember_page_types(state, window_id, term) do
    if MapSet.member?(state.page_windows, window_id) do
      %{state | page_types: MapSet.union(state.page_types, Registry.entity_types(term))}
    else
      state
    end
  end

  defp first_round(state, window_id, 0) do
    Evaluator.round(window_id, [])

    state
  end

  defp first_round(state, window_id, version), do: deliver(state, window_id, version)

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
  defp reread_type(entity_type, state, synced_types, trust_held?) do
    {rows, read_seq} =
      state.read_fill.(entity_type, state.actor_user_id, state.replica_id, synced_types)

    read_pairs = &Live.pairs_touching(&1, synced_types)

    {news, pot} =
      Pot.reread(state.pot, entity_type, rows, read_pairs, trust_held?: trust_held?)

    # Read after the batch, so its rows can hold batches of this client's the session hasn't told:
    # their frames claim the number the read found, and the session keeps its own (see
    # `tell_part/2`).
    send_news(%{state | pot: pot}, news, %{}, higher_seq(state.applied_seq, read_seq))
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
  defp send_news(state, %{edges: edges} = news, verdicts, claim)
       when claim != state.applied_seq and edges != [] do
    state
    |> send_frames(%{news | edges: []}, verdicts, claim)
    |> send_frames(
      %{appeared: [], edges: edges, patched: [], unsynced: []},
      verdicts,
      state.applied_seq
    )
  end

  defp send_news(state, news, verdicts, claim), do: send_frames(state, news, verdicts, claim)

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
    send(state.client, {:sync_deltas, cursor, deltas, claim})

    %{state | unsent: nil}
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
  # judged against it, so one the same later batch overtook goes out whole too. The fill and the
  # catch-up raise it from their own reads, which is safe because the edge is read after them: a
  # part such a batch can overtake starts below the edge, and goes out whole (see `trusts_held?/2`).
  defp tell_part(state, part) do
    own_seq = state.replica_id && Map.get(part.own_seqs, state.replica_id)
    overtaking_seq = state.replica_id && Map.get(part.overtaking_seqs, state.replica_id)

    placed = %{
      state
      | applied_seq: higher_seq(state.applied_seq, own_seq),
        place: max_place(state.place, part.place)
    }

    overtaken? = overtaken?(placed.applied_seq, overtaking_seq)
    trust_held? = trusts_held?(placed, part) and not overtaken?
    {news, pot} = Pot.decide(placed.pot, part, trust_held?: trust_held?)

    # A row handed over whole travels with its verdicts, and none held is patched when held isn't
    # trusted. The verdicts are the part's, read in the batch's recheck.
    stale =
      if trust_held? do
        placed.pot
        |> Pot.verdict_rows(part)
        |> Verdicts.moved(placed.told_verdicts)
      else
        []
      end

    decided = %{placed | pot: pot}
    claim = if overtaken?, do: overtaking_seq, else: placed.applied_seq
    news_with_verdicts = %{news | patched: Verdicts.patches(news.patched, stale)}

    told = send_news(decided, news_with_verdicts, part.verdicts, claim)

    # A reread is judged by the edge alone: its frames claim its own read's number, so a later
    # batch of this client's that overtook the part leaves its rows as true as they are.
    reread_trust? = trusts_held?(placed, part)

    part.whole_types
    |> Enum.reduce(told, &reread_type(&1, &2, part.synced_types, reread_trust?))
    |> flush_frames()
  end

  defp overtaken?(_told_seq, nil), do: false

  defp overtaken?(nil, _overtaking_seq), do: true

  defp overtaken?(told_seq, overtaking_seq), do: overtaking_seq > told_seq

  # Whether what the session holds can be trusted to say what the client holds of the batch's rows.
  # Not for a batch with a transaction below the edge read once the fill or the catch-up was over.
  # The fill read each type at its own moment, so such a transaction can be in the rows of some
  # types and not in those read before it committed - a row it made readable was sent with the type
  # read after it, while the rows read before named nothing of it. A catch-up takes its client to
  # hold what the user may read when it reads that, which a transaction committing around it can
  # make true of a row the client never got. Such a batch hands every row it may read over whole,
  # which restates its sets and tells the pairs filed under the rows read before (see
  # `Hologram.Sync.Pot.decide/3`).
  defp trusts_held?(%{trust_edge: nil}, _part), do: true

  defp trusts_held?(%{trust_edge: trust_edge}, %{tx_range: {lowest, _highest}}) do
    lowest >= trust_edge
  end

  defp max_place(nil, place), do: place

  defp max_place(place, other_place), do: max(place, other_place)
end
