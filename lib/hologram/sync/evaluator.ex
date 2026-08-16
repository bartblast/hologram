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
  """
  @spec round(String.t(), list({non_neg_integer, list(map)})) :: :ok
  def round(window_id, transactions) do
    case Registry.lookup(@registry, window_id) do
      [{pid, _value}] -> GenServer.cast(pid, {:round, transactions})
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
      [{pid, _value}] -> GenServer.call(pid, {:subscribe, subscriber})
      [] -> :no_evaluator
    end
  end

  @impl GenServer
  def init(opts) do
    subscribers =
      opts
      |> Keyword.get(:subscribers, [])
      |> Map.new(&{&1, Process.monitor(&1)})

    state = %{
      subscribers: subscribers,
      term: Keyword.fetch!(opts, :term),
      version: 0,
      window_id: Keyword.fetch!(opts, :window_id)
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
  def handle_cast({:round, transactions}, state) do
    # Rounds that piled up while one was running are answered by the run about to happen: it
    # reads the database as it stands, which is after all of them, and what they carry is which
    # attributes moved - so they are merged rather than dropped.
    {:noreply, run(state, transactions ++ drain_rounds([]))}
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

  defp drain_rounds(transactions) do
    receive do
      {:"$gen_cast", {:round, more}} -> drain_rounds(transactions ++ more)
    after
      0 -> transactions
    end
  end

  defp run(state, transactions) do
    version = state.version + 1
    rows = QueryRunner.run(state.term, DB.mapping())

    ResultStore.put(state.window_id, version, rows)

    # The rows themselves are never sent: a message is copied into every receiving process, which
    # would undo the point of holding one shared copy of them.
    Enum.each(state.subscribers, fn {subscriber, _ref} ->
      send(subscriber, {:round, state.window_id, version, transactions})
    end)

    %{state | version: version}
  end
end
