defmodule Hologram.Sync.Session do
  @moduledoc false

  # One per connected client. It holds what that client has been told - which rows, of which
  # windows - and turns each shared round into the part of it that is this client's news.
  #
  # What it keeps is membership, never rows: the rows live once per node in the result store,
  # and a hundred sessions reading one window read that one copy. The one exception is a returning
  # client's catch-up, which keeps the hidden rows that left a window and the rows that entered one
  # until it is over, bounded by what moved meanwhile.
  #
  # A client is given every window this build downloads, not only the ones its page reads: a page
  # it navigates to is then answered from what it already has, with no server in the way. The page
  # decides ORDER - its own windows fill first, the rest follow - so what the client is looking at
  # is ready first and the rest arrives while it reads.

  use GenServer, restart: :temporary

  alias Hologram.Auth
  alias Hologram.Entity
  alias Hologram.Policy
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
  alias Hologram.Sync.Diff
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.Frame
  alias Hologram.Sync.PageWindows
  alias Hologram.Sync.ResultStore
  alias Hologram.Sync.Verdicts

  @doc """
  Starts a session for a client on the given `:page`, telling `:client` what changes for it.

  `:actor_user_id` is who the client is, or nil for an anonymous one - every row is checked
  against it before being sent, so what the client named as its page decides only the order the
  windows fill in, never what it may see of them.

  `:fill_place` is where the log stood when this session's windows were taken up - what every
  window's place starts at, so a window that has had no round of its own still holds the frames
  back to a place its rows are known to cover. Without it a batch already routed but not yet
  delivered would fall outside every claim a frame makes.

  `:policy_hash` is the hash of the rules this session judges rows by (see
  `Hologram.Policy.hash/0`), taken once where the session is started and stamped on every place a
  frame hands over: a place is a claim about what the client holds, and what it holds is what these
  rules let it see. Taken once rather than read per frame, because the rules can change under a
  running session - a live reload does that - and a place stamped with the new rules would vouch
  for rows the old ones decided.

  `:replica_id` is the browser's own copy of the data, when the client presented one this stream
  could vouch for - it is what tells this session's frames which of the effects they carry are
  that browser's own doing. Absent for a client that presented none, and then no frame names a
  number at all.

  `:applied_seq` is how far that replica's batches had been applied when this session began. A
  session cannot work it out from the rounds it sees: the first fill is read from the rows as
  they stand, and the batches behind those values were applied before anything here was watching.
  Read where the replica is identified and handed over, rather than looked up here, since the
  process identifying the replica already reads the database for it.

  A frame carries the place the client may resume from only once it holds a whole pot: mid-fill
  there is nothing coherent to resume from, and a place handed over early is a claim the client
  cannot honour.

  `:read_gap` reads what a returning client missed - absent for one arriving with nothing, in which
  case every row it may see is sent. It answers what `Hologram.Sync.Catchup.gap/3` answers: the
  effects since the client's place and the grants it held there, or why it has to be sent
  everything again, which ends the session with `{:full_resync, reason}` so the client comes back
  through the doors. Given one, the client keeps what it already holds and is told only about the
  rows the gap names. Handed over as a reader rather than as the effects, because the log is read
  only once every window has filled - a change committed while they fill is then in the gap rather
  than lost between the rounds a catching-up session passes over - and the read runs in this
  process. Whether a gap can be had at all is decided before the session starts, since it is a
  question about the log rather than about this client - the session's own read finding it can't
  is the log having moved since, a gap that outgrew a replay or a deploy landing in between.

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
      cut: nil,
      departed: %{},
      edges: Keyword.get(opts, :edges),
      fill_place: Keyword.get(opts, :fill_place),
      gap_end: Keyword.get(opts, :gap_end),
      held: %{},
      page: Keyword.fetch!(opts, :page),
      page_windows: MapSet.new(),
      pending: MapSet.new(),
      places: %{},
      policy_hash: Keyword.fetch!(opts, :policy_hash),
      read_gap: read_gap,
      replica_id: Keyword.get(opts, :replica_id),
      resuming: read_gap != nil,
      told_verdicts: %{},
      verdicts_checked: nil,
      versions: %{}
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl GenServer
  def handle_continue(:subscribe, state) do
    page_window_ids = PageWindows.lookup(state.page)
    background_window_ids = PageWindows.all() -- page_window_ids
    window_ids = page_window_ids ++ background_window_ids

    # Every window counts as outstanding before any of them is taken up, so one that fills while
    # the others are still being taken up cannot empty the set and say the client has everything.
    seeded = %{
      state
      | page_windows: MapSet.new(page_window_ids),
        pending: MapSet.new(window_ids),
        places: Map.new(window_ids, &{&1, state.fill_place})
    }

    # A client with nothing to wait for is told so at once: one left waiting for a marker that
    # never comes would never read its own store.
    subscribed = Enum.reduce(window_ids, announce(seeded), &subscribe_to_window/2)

    {:noreply, subscribed}
  end

  @impl GenServer
  def handle_info({:cut, reason}, state) do
    {:stop, reason, state}
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
  # included. The round that cut it has already moved its window's place past itself, so any frame
  # would claim a place past a change nobody told the client - and a later round of that same
  # window, still in the store, would tell only its own changes while claiming its own place.
  def handle_info({:round, _window_id, _version, _transactions, _place}, %{cut: cut} = state)
      when cut != nil do
    {:noreply, state}
  end

  def handle_info({:round, window_id, version, transactions, place}, state) do
    events = Enum.flat_map(transactions, fn {_tx, events} -> events end)

    updated =
      state
      |> remember_place(window_id, place)
      |> remember_applied(events)

    {:noreply, deliver(updated, window_id, version, transactions)}
  end

  # A cut met while the windows are still being taken up leaves the rest of them to be subscribed
  # to, and nothing of theirs is told either.
  defp deliver(%{cut: cut} = state, _window_id, _version, _transactions) when cut != nil do
    state
  end

  defp deliver(state, window_id, version, transactions) do
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
        held = Map.get(state.held, window_id, %{})

        held_ids =
          held
          |> Map.keys()
          |> MapSet.new()

        deltas = Diff.deltas(result, held_ids, state.actor_user_id, transactions)

        state
        |> remember_moved(window_id, result)
        |> remember_version(window_id, version)
        |> send_deltas(window_id, deltas, transactions)
        |> remember(window_id, held, deltas)
        |> mark_filled(window_id)
    end
  end

  # A row is dropped only once it has left every window this client holds - one window losing it
  # while another still carries it is not news, and telling the client to drop it would take the
  # row out from under the query that still wants it. What a window holds is the whole of its
  # REACH: a row carried only through an include counts the same as a root.
  defp left_the_pot(state, window_id, vanished) do
    others = Map.delete(state.held, window_id)

    Enum.reject(vanished, fn id ->
      Enum.any?(others, fn {_window_id, held} -> Map.has_key?(held, id) end)
    end)
  end

  # A client being caught up is told nothing until it is: what it holds is stale until the gap
  # lands, and a marker saying otherwise would have it read a store that lies. Once every window
  # has reported, what the client may see is known, and the gap can be read and spoken.
  #
  # A session on its way out says nothing more: the client comes back through the doors, and
  # anything told in between is told again there.
  defp announce(%{cut: nil} = state) do
    cond do
      not replaying?(state) ->
        announce_scopes(state)

      Enum.empty?(state.pending) ->
        catch_up(state)

      true ->
        state
    end
  end

  defp announce(state), do: state

  # Two scopes rather than one marker per window: what a client needs to know is whether it can
  # answer a page from its own store, and window ids are the server's business - they never cross
  # the wire. `:page` means the page the client is on is answerable, `:all` means every page is.
  defp announce_scopes(state) do
    state
    |> announce_scope(:page)
    |> announce_scope(:all)
  end

  # The marker carries the place, and the place is computed from the state that ALREADY records
  # the scope as announced - `cursor/1` answers nil until the client holds a whole pot, and
  # announcing `:all` is precisely what makes that true. Computed from `state` instead, the frame
  # that says "you have everything" would be the one frame unable to say where everything ends.
  defp announce_scope(state, scope) do
    filled? =
      state
      |> outstanding(scope)
      |> Enum.empty?()

    if filled? and not MapSet.member?(state.announced, scope) do
      announced = %{state | announced: MapSet.put(state.announced, scope)}

      send(announced.client, {:sync_synced, scope, cursor(announced)})

      announced
    else
      state
    end
  end

  # The gap is read only now, once every window has filled, rather than when the session began.
  # Rounds reaching a session that is catching up tell nothing, so a change committed while the
  # windows were filling would otherwise be told by nobody: its round is passed over, and a window
  # filling after it reads it as a row that was always so. Read now, the gap names everything
  # committed before this moment, and everything after it reaches the session as a round once the
  # client is caught up.
  #
  # Two answers end the session instead: a log that can no longer tell this client what it
  # missed, and a window whose last round left the ring before the gap could be judged against it.
  defp catch_up(state) do
    case state.read_gap.() do
      {:ok, gap, grants_then} ->
        case judge_gap(state, gap, grants_then) do
          {:ok, judged} ->
            state
            |> tell_gap(judged)
            |> announce_scopes()

          :behind_the_ring ->
            cut(state, :behind_the_ring)
        end

      {:full_resync, reason} ->
        cut(state, {:full_resync, reason})
    end
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
    judged = settle(unsettled)

    # The watermark is raised by every one of this replica's effects in the gap before any frame
    # goes out, wherever the deciding read ended. Every row goes out as it stands, so an early frame
    # can carry a row with a write of this replica's that only a later frame names - and a row going
    # out with the write in it under a number saying it isn't has the client apply the write a
    # second time. A window's round can be older than one of these writes, and the client then
    # shows the row from before its write until that window's round arrives.
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
  # see, has left every window - what a connected client is told when a row leaves the last
  # window holding it. Only a row the client may hold is taken away: one it could see in the round
  # it left, or a hidden one it could see before it went away, under the grants it held then or
  # before a related row the gap names moved - which, like the reach of the rows a last round
  # carries, errs towards taking away. So does a row that entered a window during the catch-up
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

    {visible, hidden} =
      state.departed
      |> Enum.reject(fn {id, _departure} ->
        Map.get(judged.visibility, id, false) or MapSet.member?(told_ids, id)
      end)
      |> Enum.split_with(fn {_id, departure} -> match?({:visible, _type}, departure) end)

    held_hidden = held_hidden(hidden, state, judged)

    unsyncs =
      visible
      |> Enum.map(fn {id, {:visible, type}} -> {id, type} end)
      |> Enum.concat(held_hidden)
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
      |> forget_unsynced(deltas)
    end)
  end

  # A row that entered a window while the client was being caught up, through nothing the gap
  # names - a related row moving into a window's filter brings rows that never changed - and that
  # the client may see once every window is judged, is handed over as it stands. The window lists it
  # as held already, so no later round would. Rows the gap names or the shift hands over are spoken
  # for there.
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

  # A row a catch-up frame takes away is no longer the client's, whichever window lists it as held.
  # A window can still list a row the catch-up judged hidden - its copy read before the window that
  # hid it, or a grant or related row moving after its round was delivered - and left there, that
  # window's next round would tell the row coming back into sight as a patch, or as nothing at all,
  # to a client that no longer has it.
  defp forget_unsynced(state, frame_deltas) do
    unsynced =
      frame_deltas
      |> Enum.filter(&(&1.op == :unsync_entity))
      |> Enum.map(& &1.id)

    held =
      Map.new(state.held, fn {window_id, window_held} ->
        {window_id, Map.drop(window_held, unsynced)}
      end)

    %{state | held: held}
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
      |> forget_unsynced(deltas)
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
    |> Verdicts.stale(state.told_verdicts, state.actor_user_id, :all)
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
    |> forget_unsynced(deltas)
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

      Cursor.encode(capped_tx, capped_seq, state.policy_hash)
    end
  end

  defp mark_filled(state, window_id) do
    filled = %{state | pending: MapSet.delete(state.pending, window_id)}

    announce(filled)
  end

  defp outstanding(state, :all), do: state.pending

  defp outstanding(state, :page) do
    MapSet.intersection(state.pending, state.page_windows)
  end

  # What a frame may claim the client has reached: the SLOWEST window's place. A window's missed
  # changes can only live in batches after its last applied round, and those start at or above
  # that round's place - so replaying from the minimum covers every window's possible gap, whatever
  # order the rounds arrived in. Claiming the newest place instead would lose a slow window's
  # changes outright, which no amount of idempotent replay puts back.
  defp cursor(state) do
    if holds_a_whole_pot?(state) do
      place =
        state.places
        |> Map.values()
        |> Enum.reject(&is_nil/1)
        |> Enum.min(fn -> nil end)

      case place do
        nil -> nil
        {tx, seq} -> Cursor.encode(tx, seq, state.policy_hash)
      end
    end
  end

  # A cursor is a CLAIM - "everything up to here is applied" - and the server takes it at face
  # value on the way back, replaying only what came after. A client part way through its first fill
  # cannot make that claim: it holds some windows and not others, and handing it a place would have
  # it come back asking for the little that changed since, never learning about the windows it
  # never received. Silently, and for as long as it keeps that store.
  #
  # So frames carry no place until the client has a whole pot to date it - which is true from the
  # start for one that arrived WITH a gap, since it kept what it already had, and true for a first
  # arrival once every window has reported.
  defp holds_a_whole_pot?(state) do
    state.resuming or MapSet.member?(state.announced, :all)
  end

  # The last place each window has applied, taken forward only - a slow round arriving late must
  # not drag a window's place backwards, and both claims it could make are sound, so the further
  # one is kept. What a frame may claim is the MINIMUM of these: a window's missed changes can
  # only live in batches after its last applied round, so replaying from the slowest window's
  # place covers every window's possible gap. A fill round carries no place and changes nothing.
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

  # What each window's last round was, read at its next round while the client is being caught up
  # and once it is - after that, nothing asks.
  defp remember_version(%{catching_up: true} = state, window_id, version) do
    %{state | versions: Map.put(state.versions, window_id, version)}
  end

  defp remember_version(state, _window_id, _version), do: state

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

  defp remember_moved(state, _window_id, _result), do: state

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

  defp remember_place(state, _window_id, nil), do: state

  defp remember_place(state, window_id, place) do
    places = Map.update(state.places, window_id, place, &max(&1, place))

    %{state | places: places}
  end

  # Each id is held under its type, because a row that later leaves is no longer there to name
  # its own - the arrival is the one moment the type is in hand, so it is kept from there.
  defp remember(state, window_id, held, deltas) do
    arrived = Map.new(deltas.appeared, &{&1.id, &1.__struct__})

    window_held =
      held
      |> Map.merge(arrived)
      |> Map.drop(deltas.vanished)

    %{state | held: Map.put(state.held, window_id, window_held)}
  end

  # What a frame told of the server's verdicts, kept so a later round tells only what moved.
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

  defp replaying?(state), do: state.catching_up

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

  defp gap_ids(%{data: %{"target_id" => target_id}, entity_id: entity_id, op: op})
       when op in [:add_relationship, :del_relationship] do
    [entity_id, target_id]
  end

  defp gap_ids(effect), do: [effect.entity_id]

  # A round reaching a client still being caught up tells nothing: the gap, read once every window
  # has filled, names whatever it changed, and is judged against the window's last round. What the
  # round still keeps is what the window holds and the rows that left or entered it (see
  # `remember_moved/3`).
  defp send_deltas(state, window_id, deltas, transactions) do
    if replaying?(state) do
      state
    else
      tell(state, window_id, deltas, transactions)
    end
  end

  # The rows a round patches carry the verdicts that moved for them, and a row whose verdicts moved
  # while none of its values did is patched with those alone - worked out again only for the rows
  # whose deciding quantifiers read a type the round touched.
  defp tell(state, window_id, deltas, transactions) do
    held = Map.get(state.held, window_id, %{})
    unsynced = left_the_pot(state, window_id, deltas.vanished)

    {patched, checked_state} = patched_with_verdicts(state, deltas, transactions)

    news = %{
      appeared: deltas.appeared,
      edges: deltas.edges,
      patched: patched,
      unsynced: Enum.map(unsynced, &{&1, Map.fetch!(held, &1)})
    }

    news
    |> split_news()
    |> Enum.reduce(checked_state, fn part, acc ->
      frame_deltas = Frame.deltas(part, acc.actor_user_id)

      send(acc.client, {:sync_deltas, cursor(acc), frame_deltas, acc.applied_seq})

      remember_verdicts(acc, frame_deltas)
    end)
  end

  # One batch of transactions reaches every window it touched as a round of its own, so a row
  # several windows hold is worked out once per batch - the first of its windows to report
  # answers for the rest.
  defp patched_with_verdicts(state, deltas, transactions) do
    batch = Enum.map(transactions, fn {tx, _events} -> tx end)

    checked =
      case state.verdicts_checked do
        {^batch, ids} -> ids
        _earlier_batch -> MapSet.new()
      end

    events = Enum.flat_map(transactions, fn {_tx, events} -> events end)
    changed_types = MapSet.new(events, & &1.type)
    # The rows whose own values or pairs moved, a pair naming a row on each side.
    moved_ids =
      events
      |> Enum.flat_map(&gap_ids/1)
      |> MapSet.new()

    unchecked = Enum.reject(deltas.held, &MapSet.member?(checked, &1.id))

    stale =
      Verdicts.stale(
        unchecked,
        state.told_verdicts,
        state.actor_user_id,
        changed_types,
        moved_ids
      )

    patches = Verdicts.patches(deltas.patched, stale)
    now_checked = Enum.reduce(unchecked, checked, &MapSet.put(&2, &1.id))

    {patches, %{state | verdicts_checked: {batch, now_checked}}}
  end

  # A window's first round hands over every row the client may see of it, and a whole window in one
  # frame is a frame as big as the app's data - the memory it costs is unbounded in exactly the way
  # a replay's was. Rows that APPEARED are the part that grows, so they are split across frames and
  # everything else rides with the first.
  #
  # Nothing here dates a partial fill: `cursor/1` already answers nil until the client holds a whole
  # pot, so a client cut off between two of these frames comes back with no place and is filled
  # again. That is the honest answer while the frames are all a client has - it cannot yet say what
  # it kept.
  #
  # TODO: step 07 owns what a client DOES with a partial fill, and may want more from these frames
  # than they carry - a marker saying which window a batch belongs to, or how many are still coming,
  # so a store can commit progress rather than discarding it on a cut connection. Settle that
  # against the local store's design rather than guessing here: the shape is cheap to add and
  # expensive to change once a client reads it.
  #
  # TODO: a resync's fill is the same code path, so the same question applies to what a client
  # discards and when. Today it discards on the marker and refills from nothing.
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
        # Its place is dropped along with it. What a frame claims is the place of the window
        # furthest behind, and a window that will never have a round never moves - so left among
        # them it would hold every claim at the place this session started from. The client would
        # replay from there on each reconnect, from further back every time, until the gap outgrew
        # what the log still covers and it was sent everything again. A window with no rounds has
        # no missed changes for a claim to cover.
        unconstrained = %{state | places: Map.delete(state.places, window_id)}

        mark_filled(unconstrained, window_id)

      {:ok, evaluator, version, _term} ->
        # Watched from here on: an evaluator that stops is the end of a window's rounds, and a
        # session not told would hold that window pending for as long as the client stayed - never
        # announcing a scope, never sending a marker, with nothing the client could do about it.
        Process.monitor(evaluator)

        first_round(state, window_id, version)
    end
  end

  defp first_round(state, window_id, 0) do
    Evaluator.round(window_id, [])

    state
  end

  defp first_round(state, window_id, version), do: deliver(state, window_id, version, [])
end
