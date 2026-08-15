defmodule Hologram.Sync.Dispatcher do
  @moduledoc false

  # Reads the effect log forward, one window at a time, and hands each window's transactions to
  # whoever routes them. One of these runs per node: the log is shared, the reading is not, and
  # two nodes reading it need no agreement because each keeps its own place.

  use GenServer

  alias Hologram.DB.Outbox

  @doc """
  Starts the dispatcher.

  `:handler` is called with the transactions of each window - a list of `{transaction id,
  effects}` pairs, never empty - and is required, since a dispatcher with nowhere to send what it
  reads would advance its place past effects nobody saw.

  `:cursor` is where reading starts, and defaults to wherever the log's edge is when the first
  window is read: a node begins with what happens from then on, because what came before is what
  a client's first sync reads from the rows themselves. Starting touches no database, so the
  dispatcher can be supervised alongside the pool rather than after it.
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
    handler = Keyword.fetch!(opts, :handler)

    {:ok, %{cursor: Keyword.get(opts, :cursor), handler: handler}}
  end

  @impl GenServer
  def handle_info(:wake, state) do
    # Draining first is what makes the drain safe: the window read after it covers everything
    # committed by then, so the wakes dropped here asked for nothing this round will not do. A
    # wake arriving after the read stays in the mailbox and gets its own round, which is the
    # transaction that committed while this one was working.
    drain_wakes()

    {:noreply, dispatch(state)}
  end

  defp dispatch(state) do
    edge = Outbox.current_xmin()
    # Reading from the edge on the first round is what "from now on" means: the window it opens
    # is empty, and everything committed after it belongs to the rounds that follow.
    cursor = state.cursor || edge

    case Outbox.read_window(cursor, edge) do
      [] ->
        %{state | cursor: edge}

      transactions ->
        # The place moves only once the handler has taken them: crashing halfway means reading
        # the same window again, which routing must tolerate, rather than passing it silently.
        state.handler.(transactions)

        %{state | cursor: edge}
    end
  end

  defp drain_wakes do
    receive do
      :wake -> drain_wakes()
    after
      0 -> :ok
    end
  end
end
