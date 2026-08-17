defmodule Hologram.Sync.Evaluators do
  @moduledoc false

  # Where a session gets the evaluator of a window it needs: the first session to want one starts
  # it, every session after that joins the one already running. Starting on demand rather than up
  # front is what keeps a node's work proportional to what its clients are actually looking at,
  # rather than to how many windows the whole app declares.

  use DynamicSupervisor

  alias Hologram.DB.QueryCache
  alias Hologram.Sync.Evaluator

  @doc """
  Returns every window this node is currently keeping up to date, as the `{window id, term}`
  pairs the scoper takes.

  A window is live exactly while its evaluator runs, and an evaluator runs exactly while some
  session holds it - so this needs no bookkeeping of its own to stay true, and a session that
  crashes takes its windows with it rather than leaving a count nothing reclaims.
  """
  @spec live() :: list({String.t(), map})
  def live do
    Evaluator.registry()
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.map(&{&1, QueryCache.window(&1)})
    |> Enum.reject(fn {_window_id, term} -> is_nil(term) end)
  end

  @doc """
  Subscribes the given process to the evaluator of the given window, starting it if this is the
  first session to want it, and returns the evaluator with the round it is on - zero when it has
  just been started and has not run yet - and the term the window downloads.

  The term is handed back rather than left to be looked up again: it is what decided the window
  exists, and a live reload can drop a window between two reads of the cache, so a second look
  can answer nothing where the first answered a term.

  Answers `:no_window` for an id no registered query downloads - what a client names is its own
  claim, and one naming something unknown is told about nothing rather than refused.
  """
  @spec subscribe(String.t(), pid) :: {:ok, pid, non_neg_integer, map} | :no_window
  def subscribe(window_id, subscriber) do
    case QueryCache.window(window_id) do
      nil ->
        :no_window

      term ->
        {:ok, evaluator, version} = subscribe_to_running(window_id, term, subscriber)

        {:ok, evaluator, version, term}
    end
  end

  @doc """
  Starts the supervisor evaluators run under.
  """
  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # Two sessions wanting one window at the same moment both try to start it, and the loser is
  # told who won - so the answer is the running evaluator either way. A subscriber given at start
  # is watched from the beginning, which leaves no gap in which an evaluator could find itself
  # with nobody and stop.
  #
  # Nothing catches an answer other than these two. Starting cannot be refused here: the children
  # are unlimited, and an evaluator's init/1 takes what this line hands it and returns. An answer
  # that surprises this clause is this build being wrong about itself, which is worth the crash -
  # the alternative is calling it :no_window, and a window said not to exist is one the session
  # marks filled and announces the pot complete without.
  defp subscribe_to_running(window_id, term, subscriber) do
    child = {Evaluator, window_id: window_id, term: term, subscribers: [subscriber]}

    case DynamicSupervisor.start_child(__MODULE__, child) do
      {:ok, pid} ->
        {:ok, pid, 0}

      {:error, {:already_started, pid}} ->
        case Evaluator.subscribe(window_id, subscriber) do
          {:ok, version} ->
            {:ok, pid, version}

          # The one it lost the race to stopped before it could be joined - its last subscriber
          # went away in between. There is nothing to join now, so the window wants starting
          # again, which the retry does with this subscriber watched from the first moment.
          :no_evaluator ->
            subscribe_to_running(window_id, term, subscriber)
        end
    end
  end
end
