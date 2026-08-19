defmodule Hologram.Sync.Evaluator do
  @moduledoc false

  # One per window a node is keeping up to date, however many sessions want it. A round runs the
  # window's query once, writes the rows where every session can read them, and tells the
  # sessions which round to look at - so a window wanted by a hundred clients costs one query and
  # one copy of its rows rather than a hundred of each.
  #
  # The query runs RAW: what each client may see of the result is decided per client, against the
  # rows, rather than by running a hundred differently-filtered queries.

  use GenServer, restart: :temporary

  alias Hologram.DB
  alias Hologram.DB.QueryRunner
  alias Hologram.Sync.ResultStore

  @registry Hologram.Sync.EvaluatorRegistry

  @doc """
  Returns the registry evaluators are found by, keyed by window id.
  """
  @spec registry() :: atom
  def registry, do: @registry

  @doc """
  Tells the evaluator of the given window that the given transactions may have changed its
  answer. Telling one that is not running does nothing: a window nobody holds has nobody to tell.

  The place is where the batch was read from, or nil for a round asked for by a session rather
  than by the log - a fill has no batch, and claims no place.
  """
  @spec round(
          String.t(),
          list({non_neg_integer, list(map)}),
          {non_neg_integer, non_neg_integer} | nil
        ) :: :ok
  def round(window_id, transactions, place \\ nil) do
    case Registry.lookup(@registry, window_id) do
      [{pid, _value}] -> GenServer.cast(pid, {:round, transactions, place})
      [] -> :ok
    end
  end

  @doc """
  Starts the evaluator of the window the given `:window_id` and `:term` describe.

  `:subscribers` are the processes to tell about each round. They are monitored, so a session
  that goes away stops being told - and an evaluator that runs out of subscribers stops, since
  nobody is left to read what it would produce.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    window_id = Keyword.fetch!(opts, :window_id)

    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {@registry, window_id}})
  end

  @doc """
  Adds a subscriber to the evaluator of the given window and returns the round it is on, or
  `:no_evaluator` when nothing holds the window.

  A subscriber joining an evaluator that has already run reads that round rather than asking for
  another - zero means no round has happened yet, and whoever gets it asks for the first.
  """
  @spec subscribe(String.t(), pid) :: {:ok, non_neg_integer} | :no_evaluator
  def subscribe(window_id, subscriber) do
    case Registry.lookup(@registry, window_id) do
      [{pid, _value}] -> ask_to_subscribe(pid, subscriber)
      [] -> :no_evaluator
    end
  end

  @impl GenServer
  def init(opts) do
    # A round runs the window's query on a borrowed connection, and an exit signal reaching a
    # process that does not trap kills it where it stands - mid-query, taking that connection down
    # with it and everything pooled behind it. Trapping turns the signal into a message, which
    # queues behind the round in flight: the query finishes, the connection goes back, and the
    # stop happens between callbacks rather than inside one.
    #
    # No terminate/2 comes with it, deliberately. Nothing is cleaned up on the way out - what an
    # evaluator leaves behind is cleared by the NEXT one at start, below, because that is the one
    # moment reachable however the last one ended.
    Process.flag(:trap_exit, true)

    window_id = Keyword.fetch!(opts, :window_id)

    # Rounds are counted from zero again here, so whatever the store still holds for this window
    # was written by an evaluator that is gone and can never be asked for again. One that stopped
    # for the ordinary reason cleared its own rows on the way out - one that was killed, or whose
    # query raised, had no way out to do it in, and its rows would otherwise sit there until a
    # replacement's count happened to climb past them, which on a quiet window is never.
    #
    # Starting is where this belongs rather than stopping, because starting is the one moment
    # reachable however the last one ended.
    ResultStore.forget(window_id)

    subscribers =
      opts
      |> Keyword.get(:subscribers, [])
      |> Map.new(&{&1, Process.monitor(&1)})

    state = %{
      subscribers: subscribers,
      term: Keyword.fetch!(opts, :term),
      version: 0,
      window_id: window_id
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe, subscriber}, _from, state) do
    if Map.has_key?(state.subscribers, subscriber) do
      {:reply, {:ok, state.version}, state}
    else
      subscribers = Map.put(state.subscribers, subscriber, Process.monitor(subscriber))

      {:reply, {:ok, state.version}, %{state | subscribers: subscribers}}
    end
  end

  @impl GenServer
  def handle_cast({:round, transactions, place}, state) do
    # Rounds that piled up while one was running are answered by the run about to happen: it
    # reads the database as it stands, which is after all of them, and what they carry is which
    # attributes moved - so they are merged rather than dropped. The merged round claims the
    # EARLIEST place among them: batches reach an evaluator in order, so that is the first one
    # carrying a place at all.
    {merged, merged_place} = drain_rounds(transactions, place)

    {:noreply, run(state, merged, merged_place)}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, subscriber, _reason}, state) do
    subscribers = Map.delete(state.subscribers, subscriber)

    if Enum.empty?(subscribers) do
      ResultStore.forget(state.window_id)

      {:stop, :normal, %{state | subscribers: subscribers}}
    else
      {:noreply, %{state | subscribers: subscribers}}
    end
  end

  # A registry entry outlives the process it names by however long the registry takes to hear it
  # died, so a lookup can hand back a pid with nothing behind it - and an evaluator can stop while
  # the question is still travelling. Both are the same answer as finding no entry at all, and are
  # given as that answer rather than as an exit in whoever asked. A call that times out is left to
  # raise: an evaluator too busy to answer has not stopped, and saying it had would start a second
  # one beside it.
  defp ask_to_subscribe(pid, subscriber) do
    GenServer.call(pid, {:subscribe, subscriber})
  catch
    :exit, {reason, {GenServer, :call, _call}} when reason in [:noproc, :normal] -> :no_evaluator
  end

  defp drain_rounds(transactions, place) do
    receive do
      {:"$gen_cast", {:round, more, more_place}} ->
        drain_rounds(transactions ++ more, place || more_place)
    after
      0 -> {transactions, place}
    end
  end

  defp run(state, transactions, place) do
    version = state.version + 1
    rows = QueryRunner.run(state.term, DB.mapping())

    ResultStore.put(state.window_id, version, rows)

    # The rows themselves are never sent: a message is copied into every receiving process, which
    # would undo the point of holding one shared copy of them.
    Enum.each(state.subscribers, fn {subscriber, _ref} ->
      send(subscriber, {:round, state.window_id, version, transactions, place})
    end)

    %{state | version: version}
  end
end
