defmodule Hologram.Sync.Dispatcher do
  @moduledoc false

  # Reads the oplog forward, one window at a time, and hands each window's effects to whoever
  # routes them. One of these runs per node: the log is shared, the reading is not, and two nodes
  # reading it need no agreement because each keeps its own place.
  #
  # A window ends at the final limit (see `Hologram.Sync.FinalLimit`), the serial every save at or
  # below has ended at, so no effect can still appear in a window once it's read. The limit waits
  # only for the saves that hold the serial lock, so a long write outside Hologram delays nothing.

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

  `:handler` is called with the effects of each window, in seq order and never none, and the place
  the window was read FROM (see `Hologram.DB.Oplog.place/1`), which is what a frame built from
  these effects may claim a client has reached: a client replaying from there gets this whole batch
  again, and never less. It is required, since a dispatcher with nowhere to send what it reads
  would advance its place past effects nobody saw.

  `:cursor` is the place reading starts from, and defaults to the first final limit, worked out in
  a round run as this dispatcher STARTS: a node begins with what happens from then on, because what
  came before is what a client's first sync reads from the rows themselves. Until that round ends,
  which a save running at the start can hold back, the dispatcher reads nothing, and no session can
  start (see `Hologram.Sync.Session`).

  Begun at the start rather than at the first wake, and the difference is a hole rather than a
  nicety. What wakes the dispatcher is usually the very append a client is waiting for - a limit
  worked out then can stand above that append and pass it by, for good. A client that filled from
  the rows before it and holds a store missing it would go on holding one until some later write to
  the same window happened to refresh it.

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
  at the edge as it stands would skip the window the last one was reading. It is optional: without
  one the edge lives in this process alone, and dies with it.

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
      # The id of the log the place is in, taken from the first round's run when the place isn't
      # resumed (see `Hologram.DB.Oplog.log_id/0`).
      log_id: nil,
      # The id a loss was found under while giving the log a new one failed, which every round
      # tries again before it reads anything (see `recover_from_loss/2`).
      pending_rotation: nil,
      read_edge: Keyword.get(opts, :read_edge),
      recheck_interval_ms: Keyword.get(opts, :recheck_interval_ms, @default_recheck_interval_ms),
      recheck_scheduled: false,
      rotate_log_id: Keyword.get(opts, :rotate_log_id, &Oplog.rotate_log_id/1)
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

    {:noreply, dispatch(%{state | cursor: cursor, log_id: log_id})}
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

    state
    |> Map.put(:limit, limit)
    |> check_loss(state.limit)
    |> watch_prepared(FinalLimit.holders(limit))
  rescue
    # A hot standby can't read the unlogged table naming the server's run, and a restore has the
    # system tables dropped for a while. Neither moves the log, so the limit stays where it was and
    # the next round tries again.
    error in [DBConnection.ConnectionError, MatchError, Postgrex.Error] ->
      Logger.debug("Hologram: the final limit wasn't worked out: " <> Exception.message(error))

      state
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

  defp dispatch(state) do
    advanced = advance_limit(state)

    advanced
    |> read_to(FinalLimit.place(advanced.limit))
    |> schedule_recheck()
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

    %{state | cursor: nil, limit: FinalLimit.new(), log_id: nil}
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

  # Kept where this process dying cannot take it, as well as in the process itself: the state of
  # one that crashed is gone, and its replacement resuming at the edge would leave every session on
  # this node holding a place past a window none of them was sent.
  defp move_to(state, place) do
    if state.read_edge, do: ReadEdge.put(state.read_edge, {place, state.log_id})

    %{state | cursor: place}
  end

  defp read_to(state, nil), do: state

  # The first limit is where a dispatcher with nowhere to resume from begins.
  defp read_to(%{cursor: nil} = state, limit_place), do: move_to(state, limit_place)

  defp read_to(
         %{cursor: {from_seq, _tx, _at} = cursor} = state,
         {to_seq, _to_tx, _to_at} = limit_place
       )
       when to_seq > from_seq do
    case Oplog.read_window(from_seq, to_seq) do
      [] ->
        move_to(state, limit_place)

      effects ->
        # The place moves only once the handler has taken them: a round that crashes halfway, or is
        # skipped while the data model is held, reads the same window again, which routing must
        # tolerate, rather than passing it silently.
        state.handler.(effects, cursor)

        move_to(state, limit_place)
    end
  rescue
    # A data model under a hold can't be routed against until it is released (see
    # Hologram.Entity.Model.hold/0). The round is skipped rather than crashed, which would restart
    # this process on every round for as long as the hold stands.
    Hologram.StaleModelError -> state
  end

  defp read_to(state, _limit_place), do: state

  # The edge is cleared first, so a session joining from here on finds none and stops (see
  # `Hologram.Sync.Session`), and the sessions stopped are every one that may have read it.
  defp recover_from_loss(state, rotated_log_id) do
    if state.read_edge, do: ReadEdge.put(state.read_edge, nil)

    finish_recovery(%{state | pending_rotation: rotated_log_id})
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
