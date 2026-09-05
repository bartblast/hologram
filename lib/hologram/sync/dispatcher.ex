defmodule Hologram.Sync.Dispatcher do
  @moduledoc false

  # Reads the entity changelog forward, one window at a time, and hands each window's
  # transactions to whoever routes them. One of these runs per node: the log is shared, the
  # reading is not, and two nodes reading it need no agreement because each keeps its own
  # place.

  use GenServer

  alias Hologram.DB.EntityChangelog
  alias Hologram.Sync.ReadEdge

  # How long the log can go unread when the announcements stop arriving - a listener whose
  # connection died, or a pooler that drops them. It bounds nothing while they do arrive, since
  # each one is read immediately, and a round over an unchanged log is two cheap reads. Policy,
  # not a derived figure: it trades those reads against how stale a client can get while the
  # announcements are missing.
  @default_poll_interval_ms :timer.seconds(5)

  @doc """
  Starts the dispatcher.

  `:handler` is called with the transactions of each window - a list of `{transaction id,
  effects}` pairs, never empty - and the place the window was read FROM, which is what a frame
  built from these transactions may claim a client has reached: a client replaying from there
  gets this whole batch again, and never less. It is required, since a dispatcher with nowhere to
  send what it reads would advance its place past effects nobody saw.

  `:cursor` is where reading starts, and defaults to wherever the log's edge stood when this
  dispatcher STARTED: a node begins with what happens from then on, because what came before is
  what a client's first sync reads from the rows themselves.

  Read at the start rather than at the first round, and the difference is a hole rather than a
  nicety. The first round comes when something wakes it, and what wakes it is usually the very
  append a client is waiting for - reading the edge then opens a window above that append and
  passes it by, for good. A client that filled from the rows before it and holds a store missing
  it would go on holding one until some later write to the same window happened to refresh it.

  `:notifications` names a `Postgrex.Notifications` process to hear appends on. It is optional
  because the announcements are an optimization over the poll rather than the mechanism: without
  one the dispatcher still reads, just no sooner than `:poll_interval_ms` after a write.

  `:read_edge` names a `Hologram.Sync.ReadEdge` process keeping how far the log has been read,
  which is what a dispatcher put there before this one started resumes from - a restart that began
  at the edge as it stands would skip the window the last one was reading. It is optional: without
  one the edge lives in this process alone, and dies with it.
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
      cursor: Keyword.get(opts, :cursor),
      handler: Keyword.fetch!(opts, :handler),
      notifications: Keyword.get(opts, :notifications),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, default_poll_interval_ms()),
      read_edge: Keyword.get(opts, :read_edge)
    }

    {:ok, state, {:continue, :start_listening}}
  end

  @impl GenServer
  def handle_continue(:start_listening, state) do
    if state.notifications, do: listen_for_appends(state.notifications)

    schedule_poll(state.poll_interval_ms)

    # Here rather than in init/1, so that the supervisor starting this dispatcher waits on nothing
    # but the process being spawned. Nothing can be read before it: a continue runs ahead of every
    # message, including the poll just scheduled - so whatever this settles on is where the first
    # round reads FROM, and no append can slip in above it in the meantime.
    {:noreply, %{state | cursor: starting_place(state)}}
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

  defp dispatch(state) do
    edge = EntityChangelog.current_xmin()

    case EntityChangelog.read_window(state.cursor, edge) do
      [] ->
        move_to(state, edge)

      transactions ->
        # The place moves only once the handler has taken them: crashing halfway means reading
        # the same window again, which routing must tolerate, rather than passing it silently.
        state.handler.(transactions, {state.cursor, 0})

        move_to(state, edge)
    end
  end

  defp default_poll_interval_ms do
    :hologram
    |> Application.get_env(:sync, [])
    |> Keyword.get(:poll_interval_ms, @default_poll_interval_ms)
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

  # Kept where this process dying cannot take it, as well as in the process itself: the state of
  # one that crashed is gone, and its replacement resuming at the edge would leave every session on
  # this node holding a place past a window none of them was sent.
  # Two answers, both of them yes: the channel is registered either way, and `:eventually` only
  # means the connection has not opened yet - the server is told as soon as it does. Refusing to
  # accept that answer would make a database still coming up fail the process that is waiting for
  # it, which is the whole reason the connection is allowed to open late.
  defp listen_for_appends(notifications) do
    case Postgrex.Notifications.listen(notifications, EntityChangelog.channel()) do
      {:ok, _ref} -> :ok
      {:eventually, _ref} -> :ok
    end
  end

  defp move_to(state, edge) do
    if state.read_edge, do: ReadEdge.put(state.read_edge, edge)

    %{state | cursor: edge}
  end

  defp remembered(nil), do: nil

  defp remembered(read_edge), do: ReadEdge.get(read_edge)

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  # Where this dispatcher begins: what it was told, or where a dispatcher it replaces got to, or
  # the log's edge as it stands right now. The last is what "from now on" means for a node that
  # has never read - and taking it HERE is what makes "now" the moment the node started rather
  # than the moment something first woke it, which is always after an append it should have seen.
  defp starting_place(state) do
    state.cursor || remembered(state.read_edge) || EntityChangelog.current_xmin()
  end

  defp wake_up(state) do
    # Draining first is what makes the drain safe: the window read after it covers everything
    # committed by then, so the wakes dropped here asked for nothing this round will not do. A
    # wake arriving after the read stays in the mailbox and gets its own round, which is the
    # transaction that committed while this one was working.
    drain_wakes()

    dispatch(state)
  end
end
