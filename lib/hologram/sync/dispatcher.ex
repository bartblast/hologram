defmodule Hologram.Sync.Dispatcher do
  @moduledoc false

  # Reads the oplog forward and hands each round's effects to whoever routes them. One of these
  # runs per node: the log is shared, the reading is not, and two nodes reading it need no agreement
  # because each keeps its own place.
  #
  # The place is the final limit (see `Hologram.Sync.FinalLimit`), the serial every save at or below
  # has ended at, so no effect can still appear at or below it once it's read. The limit waits only
  # for the saves that hold the serial lock, so a long write outside Hologram delays nothing. A save
  # running holds the limit back, but not the saves committing around it: each round sends every
  # committed effect not yet sent, above the limit too, and keeps the seqs it skipped below the
  # highest it sent, which a save still running fills once it commits.

  use GenServer

  require Logger

  alias Hologram.DB.Oplog
  alias Hologram.Sync.FinalLimit
  alias Hologram.Sync.ReadEdge

  # How long a prepared transaction holding the serial lock can hold the limit back before the
  # dispatcher says so. A two-phase commit is prepared for moments, while one its coordinator
  # abandoned holds the lock until someone commits or rolls it back by hand.
  @prepared_warning_ms :timer.minutes(1)

  # How long the log can go unread when the announcements stop arriving - a listener whose
  # connection died, or a pooler that drops them. It bounds nothing while they do arrive, since
  # each one is read immediately, and a round over an unchanged log is two cheap reads. Policy,
  # not a derived figure: it trades those reads against how stale a client can get while the
  # announcements are missing.
  @default_poll_interval_ms :timer.seconds(5)

  # How soon a round waiting for a save looks again. A save that rolls back or loses its connection
  # announces nothing, so without a look the limit would wait for the poll. Measured with the
  # limit worked out this often beside 50 busy writers, its cost is within what saves pay for their
  # serials (see the cost check in #1784).
  @default_recheck_interval_ms 10

  @doc """
  Starts the dispatcher.

  `:handler` is called with the effects of each round, in seq order, the place the round read FROM,
  what has been sent - the highest seq, and the ranges below it not sent - and the seq of the final
  limit the round read under. The place is the final limit before the round (see
  `Hologram.DB.Oplog.place/1`), which is what a frame built from these effects may claim a client
  has reached: a client replaying from there gets this whole batch again, and never less, and with
  it every effect sent above the limit before. An effect above the seq or in a range can have
  committed after the round read, so rows read for the batch can hold it; every other one at or
  below the seq has gone out, or never will. Every effect at or below the limit's seq has gone out
  once the handler has taken the round's, so a client told them holds every row numbered at or
  below it. A round reading none is handed on only when it moved the limit, with no effects, so a
  number above the limit before becomes final even when no row follows it. The handler is required,
  since a dispatcher with nowhere to send what it reads would advance its place past effects nobody
  saw.

  `:cursor` is the place reading starts from, and defaults to the first final limit, worked out in
  a round run as this dispatcher STARTS: a node begins with what happens from then on, because what
  came before is what a client's first sync reads from the rows themselves. Until that round ends,
  which a save running at the start can hold back, the dispatcher reads nothing, and no session can
  start (see `Hologram.Sync.Session`).

  Begun at the start rather than at the first wake, and the difference is a hole rather than a
  nicety. What wakes the dispatcher is usually the very append a client is waiting for - a limit
  worked out then can stand above that append and pass it by, for good. A client that filled from
  the rows before it and holds a store missing it would go on holding one until some later write to
  the same rows happened to refresh it.

  `:advance` runs one round of the final limit, `Hologram.Sync.FinalLimit.advance/1` unless given.
  Tests give their own, since a save a test's transaction runs never ends.

  `:notifications` names a `Postgrex.Notifications` process to hear appends on. It is optional
  because the announcements are an optimization over the poll rather than the mechanism: without
  one the dispatcher still reads, just no sooner than `:poll_interval_ms` after a write. That's 5
  seconds unless the option says otherwise, which only tests do.

  `:on_loss` is called when the server may have lost commits this dispatcher read: the log's id
  moved off the one its place is in (see `Hologram.DB.Oplog.log_id/0`), or the limit lost the
  entry it stood on (see `Hologram.Sync.FinalLimit.losses/1`) or came out below the place. It runs
  after the read edge is cleared and the log given a new id, and before the dispatcher reads on
  from the next final limit. The serials above what the server kept go to other saves, which a
  session dated past them would pass over, so whoever starts the sessions has them stopped here.
  It is optional, and does nothing unless given.

  `:rotate_log_id` gives the log a new id once a loss is found under the one it has,
  `Hologram.DB.Oplog.rotate_log_id/1` unless given. Tests give their own to have it fail.

  `:read_edge` names a `Hologram.Sync.ReadEdge` process keeping how far the log has been read,
  which is what a dispatcher put there before this one started resumes from - a restart that began
  at the edge as it stands would skip the effects the last one was reading. It is optional: without
  one the edge lives in this process alone, and dies with it.

  `:publish` is called with the seq every number at or below which is final, each time the place
  moves, so that queries can tell a final number from one a running save may yet be ordered below
  (see `Hologram.Sync.FinalSeq`). A round that moves the limit publishes it before the handler is
  called, so a session joining too late to be in the round's list reads it as it joins. A
  dispatcher resuming publishes its place or the limit published before it, whichever is higher,
  so a restart in the middle of a round never lowers it. It is called with 0 when the dispatcher
  starts with nowhere to resume from and once a loss is found. It is optional, and does nothing
  unless given: only the node's own dispatcher publishes.

  `:published` reads the limit last published on this node, which a dispatcher resuming publishes
  again when it is above its place. It is optional, and reads 0 unless given.

  `:recheck_interval_ms` is how soon a round waiting for a save looks again, 10 ms unless the
  option says otherwise.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc """
  Tells the dispatcher there may be something new to read.
  """
  @spec wake(GenServer.server()) :: :ok
  def wake(dispatcher) do
    send(dispatcher, :wake)

    :ok
  end

  @impl GenServer
  def init(opts) do
    state = %{
      advance: Keyword.get(opts, :advance, &FinalLimit.advance/1),
      cursor: Keyword.get(opts, :cursor),
      handler: Keyword.fetch!(opts, :handler),
      limit: FinalLimit.new(),
      notifications: Keyword.get(opts, :notifications),
      on_loss: Keyword.get(opts, :on_loss, fn -> :ok end),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms),
      prepared_since: nil,
      publish: Keyword.get(opts, :publish, fn _seq -> :ok end),
      published: Keyword.get(opts, :published, fn -> 0 end),
      # The seq last published, which nothing short of a loss publishes below.
      published_seq: 0,
      # The id of the log the place is in, taken from the first round's run when the place isn't
      # resumed (see `Hologram.DB.Oplog.log_id/0`).
      log_id: nil,
      # The id a loss was found under while giving the log a new one failed, which every round
      # tries again before it reads anything (see `recover_from_loss/2`).
      pending_rotation: nil,
      read_edge: Keyword.get(opts, :read_edge),
      recheck_interval_ms: Keyword.get(opts, :recheck_interval_ms, @default_recheck_interval_ms),
      recheck_scheduled: false,
      rotate_log_id: Keyword.get(opts, :rotate_log_id, &Oplog.rotate_log_id/1),
      # The highest seq sent, at or above the place, and the seqs between them not sent, as
      # `{first, last}` ranges in order (see `Hologram.DB.Oplog.read_unsent/2`).
      sent_through: nil,
      unsent: []
    }

    {:ok, state, {:continue, :start_listening}}
  end

  @impl GenServer
  def handle_continue(:start_listening, state) do
    if state.notifications, do: listen_for_appends(state.notifications)

    schedule_poll(state.poll_interval_ms)

    # Here rather than in init/1, so that the supervisor starting this dispatcher waits on nothing
    # but the process being spawned. Nothing can be read before it: a continue runs ahead of every
    # message, including the poll just scheduled - so the round run here notes where the log stood
    # at the start, and no append can slip in below it in the meantime.
    {cursor, log_id} = if state.cursor, do: {state.cursor, nil}, else: remembered(state.read_edge)

    # A place resumed was final when it was put, and stays final unless a loss is found, which
    # publishes 0. So does a limit a round published before it put the place and then crashed: a
    # loss clears the edge before it publishes 0, so a place resumed is from the same log. Nothing
    # to resume from leaves no number final until the first round's limit.
    resumed = publish_resumed(state, cursor)

    {:noreply, resume(%{resumed | cursor: cursor, log_id: log_id})}
  end

  @impl GenServer
  def handle_info(:wake, state) do
    {:noreply, wake_up(state)}
  end

  def handle_info({:notification, _connection, _ref, _channel, _payload}, state) do
    {:noreply, wake_up(state)}
  end

  def handle_info(:poll, state) do
    schedule_poll(state.poll_interval_ms)

    {:noreply, wake_up(state)}
  end

  def handle_info(:recheck, state) do
    {:noreply, wake_up(%{state | recheck_scheduled: false})}
  end

  defp advance_limit(state) do
    limit = state.advance.(state.limit)

    advanced =
      state
      |> Map.put(:limit, limit)
      |> check_loss(state.limit)
      |> watch_prepared(FinalLimit.holders(limit))

    {:ok, advanced}
  rescue
    # A hot standby can't read the unlogged table naming the server's run, and a restore has the
    # system tables dropped for a while. Neither moves the log, so the limit stays where it was and
    # the next round tries again.
    error in [DBConnection.ConnectionError, MatchError, Postgrex.Error] ->
      Logger.debug("Hologram: the final limit wasn't worked out: " <> Exception.message(error))

      {:error, state}
  end

  # The server may have lost commits this dispatcher read when the run names another log id than
  # the place's: a crash, a promoted standby or a restored dump changed it, or another node found a
  # loss and rotated it. That holds across a restart, which resumes with the id it read under. The
  # id already moved, so nothing rotates it. Under the same id, the server lost commits when the
  # limit lost the entry it stood on, or came out below the place read up to, and the id moves here.
  #
  # Pruning has to keep the entry the limit stands on and the log's newest entry, or a limit losing
  # its entry or coming out below the place would read as a loss and send every client everything.
  defp check_loss(state, before) do
    run_log_id = run_log_id(state.limit)
    log_id = state.log_id || run_log_id

    cond do
      run_log_id && log_id != run_log_id ->
        recover_from_loss(state, nil)

      FinalLimit.losses(state.limit) > FinalLimit.losses(before) ->
        recover_from_loss(state, log_id)

      below?(FinalLimit.place(state.limit), state.cursor) ->
        recover_from_loss(state, log_id)

      true ->
        %{state | log_id: log_id}
    end
  end

  defp below?({seq, _tx, _at}, {cursor_seq, _cursor_tx, _cursor_at}), do: seq < cursor_seq

  defp below?(_place, _cursor), do: false

  defp dispatch(%{pending_rotation: log_id} = state) when is_binary(log_id) do
    finish_recovery(state)
  end

  # A round that couldn't work out the limit reads nothing: the database it would read is as likely
  # out of reach. Nor does one that couldn't date the log, which may come from a run that lost what
  # was sent (see `Hologram.Sync.FinalLimit.counted?/1`), and the round after finds out. Nor does
  # one that found a loss and couldn't give the log a new id: its sessions are still running, under
  # a place the server may have lost.
  defp dispatch(state) do
    case advance_limit(state) do
      {:ok, advanced} ->
        if advanced.pending_rotation == nil and FinalLimit.counted?(advanced.limit) do
          advanced
          |> read_to(FinalLimit.place(advanced.limit))
          |> schedule_recheck()
        else
          schedule_recheck(advanced)
        end

      {:error, state} ->
        schedule_recheck(state)
    end
  end

  # Every announcement and every nudge asks the same question, so the ones already waiting are
  # answered by the round about to run. The poll is left where it is: dropping it would stop the
  # timer that keeps asking.
  defp drain_wakes do
    receive do
      :wake -> drain_wakes()
      {:notification, _connection, _ref, _channel, _payload} -> drain_wakes()
    after
      0 -> :ok
    end
  end

  # The id moves before the sessions are stopped, since their clients come straight back and must
  # find it moved. One that fails to move stops nothing and resets nothing: the edge stays cleared,
  # and every round tries the id again before anything else, since the round that found the loss
  # may not find it again - saves passing the place hide a limit that came out below it. The
  # dispatcher then begins again from nothing, as one with nowhere to resume from does, so the next
  # edge is put with the id read in the round that works it out, and wakes itself to run that
  # round.
  defp finish_recovery(%{pending_rotation: nil} = state) do
    send(self(), :wake)
    state.on_loss.()
    if state.read_edge, do: ReadEdge.recovered(state.read_edge)

    %{state | cursor: nil, limit: FinalLimit.new(), log_id: nil, sent_through: nil, unsent: []}
  end

  defp finish_recovery(state) do
    state.rotate_log_id.(state.pending_rotation)

    finish_recovery(%{state | pending_rotation: nil})
  rescue
    error in [DBConnection.ConnectionError, MatchError, Postgrex.Error] ->
      Logger.debug("Hologram: the log wasn't given a new id: " <> Exception.message(error))

      state
  end

  # Two answers, both of them yes: the channel is registered either way, and `:eventually` only
  # means the connection has not opened yet - the server is told as soon as it does. Refusing to
  # accept that answer would make a database still coming up fail the process that is waiting for
  # it, which is the whole reason the connection is allowed to open late.
  defp listen_for_appends(notifications) do
    case Postgrex.Notifications.listen(notifications, Oplog.channel()) do
      {:ok, _ref} -> :ok
      {:eventually, _ref} -> :ok
    end
  end

  defp max_place({seq, _tx, _at} = place, {other_seq, _other_tx, _other_at})
       when seq >= other_seq,
       do: place

  defp max_place(_place, other_place), do: other_place

  # Kept where this process dying cannot take it, as well as in the process itself: the state of
  # one that crashed is gone, and its replacement resuming at the edge would leave every session on
  # this node holding a place past effects none of them was sent.
  defp move_to(state, place) do
    if state.read_edge, do: ReadEdge.put(state.read_edge, {place, state.log_id})

    {seq, _tx, _at} = place

    %{publish_above(state, seq) | cursor: place}
  end

  # The seqs sent are taken out of the ranges not sent, and the ones skipped above the highest sent
  # before go in. Every save at or below the limit has ended, so a seq there not sent never will be.
  defp note_sent(state, seqs, sent_through, limit_seq) do
    {filled, above} = Enum.split_with(seqs, &(&1 <= sent_through))

    unsent =
      state.unsent
      |> punch(filled)
      |> Kernel.++(skipped(sent_through, above))
      |> Enum.flat_map(fn
        {_first, last} when last <= limit_seq -> []
        {first, last} -> [{max(first, limit_seq + 1), last}]
      end)

    %{state | sent_through: Enum.max([sent_through, limit_seq | above]), unsent: unsent}
  end

  # Both in order, so one walk takes every seq out of the ranges.
  defp punch(ranges, []), do: ranges

  defp punch([], _seqs), do: []

  defp punch([{first, _last} | _ranges] = ranges, [seq | seqs]) when seq < first,
    do: punch(ranges, seqs)

  defp punch([{_first, last} = range | ranges], [seq | _seqs] = seqs) when seq > last,
    do: [range | punch(ranges, seqs)]

  defp punch([{first, last} | ranges], [seq | seqs]) do
    left = if seq > first, do: [{first, seq - 1}], else: []
    right = if seq < last, do: [{seq + 1, last}], else: []

    left ++ punch(right ++ ranges, seqs)
  end

  defp read_to(%{cursor: nil} = state, nil), do: state

  # The first limit is where a dispatcher with nowhere to resume from begins.
  defp read_to(%{cursor: nil} = state, limit_place), do: move_to(state, limit_place)

  # Without a limit yet, as one resumed has until its first round ends, the effects above the place
  # go out and the place stays.
  defp read_to(state, nil), do: read_to(state, state.cursor)

  # The limit is a fact about the database once it is worked out, so it is published before the
  # sessions are listed: one registering after the list reads it as it joins, and one that read
  # before it is in the list (see `Hologram.Sync.Session`). Published before the round is read, so
  # a round skipped below keeps it noted.
  defp read_to(
         %{cursor: {cursor_seq, _tx, _at}} = state,
         {limit_seq, _limit_tx, _limit_at} = limit_place
       ) do
    final_seq = max(limit_seq, cursor_seq)

    state
    |> publish_above(final_seq)
    |> hand_on(limit_place, final_seq)
  end

  defp hand_on(%{cursor: {cursor_seq, _tx, _at} = cursor} = state, limit_place, final_seq) do
    {limit_seq, _limit_tx, _limit_at} = limit_place
    sent_through = max(state.sent_through || cursor_seq, cursor_seq)

    effects = Oplog.read_unsent(sent_through, state.unsent)
    noted = note_sent(state, Enum.map(effects, & &1.seq), sent_through, limit_seq)

    # The place moves only once the handler has taken them: a round that crashes halfway, or is
    # skipped while the data model is held, reads the same effects again, which routing must
    # tolerate, rather than passing them silently.
    if effects != [] or final_seq > cursor_seq do
      state.handler.(effects, cursor, {noted.sent_through, noted.unsent}, final_seq)
    end

    move_to(noted, max_place(cursor, limit_place))
  rescue
    # A data model under a hold can't be routed against until it is released (see
    # Hologram.Entity.Model.hold/0). The round is skipped rather than crashed, which would restart
    # this process on every round for as long as the hold stands.
    Hologram.StaleModelError -> state
  end

  # The edge is cleared first, so a session joining from here on finds none and stops (see
  # `Hologram.Sync.Session`), and the sessions stopped are every one that may have read it.
  #
  # The recovery is noted with the edge cleared, and only finishing it takes the note away: one this
  # process dies in the middle of is finished by the dispatcher replacing it (see `resume/1`).
  defp recover_from_loss(state, rotated_log_id) do
    if state.read_edge, do: ReadEdge.lose(state.read_edge, rotated_log_id)

    # Whatever was read may be lost, so no number reads as final until a new limit is worked out.
    cleared = publish_none(state)

    finish_recovery(%{cleared | pending_rotation: rotated_log_id})
  end

  # A dispatcher that died recovering from a loss left the edge cleared and the rest owed: the log
  # may still need its new id, and the sessions still run under places the server may have lost.
  # Nothing is read until that is done, as in the process that found the loss.
  defp resume(%{cursor: nil, read_edge: read_edge} = state) when read_edge != nil do
    case ReadEdge.recovery(read_edge) do
      {:recovering, log_id} -> finish_recovery(%{state | pending_rotation: log_id})
      nil -> dispatch(state)
    end
  end

  defp resume(state), do: dispatch(state)

  # A seq at or below the one last published is final already, so only a higher one is published:
  # a round without a limit yet, as one resumed has, keeps its place, which can be below the limit
  # published before it.
  defp publish_above(%{published_seq: published_seq} = state, seq) when seq <= published_seq,
    do: state

  defp publish_above(state, seq) do
    state.publish.(seq)

    %{state | published_seq: seq}
  end

  defp publish_none(state) do
    state.publish.(0)

    %{state | published_seq: 0}
  end

  # The place's seq is final: the place is the limit, or a cursor above it every save at or below
  # which was read. So is the limit published before it, which a dispatcher that crashed after
  # publishing it and before putting its place leaves above the place.
  defp publish_resumed(state, nil), do: publish_none(state)

  defp publish_resumed(state, {seq, _tx, _at}) do
    resumed_seq = max(seq, state.published.())

    state.publish.(resumed_seq)

    %{state | published_seq: resumed_seq}
  end

  defp remembered(nil), do: {nil, nil}

  defp remembered(read_edge), do: ReadEdge.get(read_edge) || {nil, nil}

  defp run_log_id(limit) do
    case FinalLimit.run(limit) do
      nil -> nil
      run -> Oplog.run_log_id(run)
    end
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  # One look at a time: a round run meanwhile, by a wake or the poll, leaves the one scheduled be.
  defp schedule_recheck(%{recheck_scheduled: false} = state) do
    if FinalLimit.waiting?(state.limit) do
      Process.send_after(self(), :recheck, state.recheck_interval_ms)

      %{state | recheck_scheduled: true}
    else
      state
    end
  end

  defp schedule_recheck(state), do: state

  defp skipped(_previous, []), do: []

  defp skipped(previous, [seq | seqs]) when seq == previous + 1, do: skipped(seq, seqs)

  defp skipped(previous, [seq | seqs]), do: [{previous + 1, seq - 1} | skipped(seq, seqs)]

  defp wake_up(state) do
    # Draining first is what makes the drain safe: the round after it notes the serials handed out
    # by then, so the wakes dropped here asked for nothing this round, or the rounds it waits on,
    # will not do. A wake arriving after the read stays in the mailbox and gets its own round,
    # which is the save that committed while this one was working.
    drain_wakes()

    dispatch(state)
  end

  # A prepared transaction names itself in pg_locks by a virtual transaction id starting with -1/,
  # since no session runs it any more. Warned of once per stretch it holds the limit back.
  defp watch_prepared(state, holders) do
    prepared? = Enum.any?(holders, &String.starts_with?(&1, "-1/"))
    now = System.monotonic_time(:millisecond)

    case {prepared?, state.prepared_since} do
      {false, _since} ->
        %{state | prepared_since: nil}

      {true, nil} ->
        %{state | prepared_since: now}

      {true, :warned} ->
        state

      {true, since} when now - since >= @prepared_warning_ms ->
        Logger.warning(
          "Hologram: a prepared transaction holding the serial lock has held back sync for " <>
            "over a minute. Commit it or roll it back (see pg_prepared_xacts)."
        )

        %{state | prepared_since: :warned}

      {true, _since} ->
        state
    end
  end
end
