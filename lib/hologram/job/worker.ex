defmodule Hologram.Job.Worker do
  @moduledoc false

  # Runs queued jobs as they are announced, one at a time. One of these runs per node, and two
  # nodes need no agreement because a claim is a locked row: whichever reads it first runs it, and
  # the other is told it is taken.

  use GenServer

  alias Hologram.DB
  alias Hologram.DB.Listener
  alias Hologram.DB.Oplog
  alias Hologram.Job.RunLock
  alias Hologram.Job.Runner
  alias Hologram.Reflection

  # How long a queued job can wait when the announcements stop arriving - a listener whose
  # connection died, or a pooler that drops them - and how long a run cut short on another node
  # stays running before a sweep here fails it. It bounds nothing else while announcements
  # arrive, since every write announces itself and is answered at once. Policy rather than a
  # derived figure: it trades a scan per interval against how late a job can run while the
  # announcements are missing, and it is the figure the dispatcher carries for the same reason.
  @default_poll_interval_ms :timer.seconds(5)

  @doc """
  Starts the worker.

  `:notifications` names a Hologram.DB.Listener connection to hear writes on. It is optional,
  because the announcements are an optimization over the poll rather than the mechanism: without
  one a job still runs, no sooner than `:poll_interval_ms` after it was created.

  `:run_lock` names the Hologram.Job.RunLock connection the worker holds its run locks on. The
  worker waits for it to connect, then gives up every lock it holds as it starts: a worker
  restarted on its own finds its predecessor's still held on a session that is still up, and the
  row of the run that crashed would look live for good.

  `:queued`, `:sweep` and `:run` are what the worker looks for jobs, fails runs cut short and runs
  a job with. They default to `Hologram.Job.Runner.queued/3`, `Hologram.Job.Runner.sweep/2` and
  `Hologram.Job.Runner.process/3`, the last on the `:run_lock` connection, so `:run_lock` is
  required when `:run` is not given. Only tests give them: the seams are what let this process be
  exercised without a database, the way the dispatcher takes the handler it routes through.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc """
  Tells the worker there may be a queued job to run.
  """
  @spec wake(GenServer.server()) :: :ok
  def wake(worker) do
    send(worker, :wake)

    :ok
  end

  @impl GenServer
  def init(opts) do
    run_lock = Keyword.get(opts, :run_lock)

    state = %{
      notifications: Keyword.get(opts, :notifications),
      passed_over: MapSet.new(),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, default_poll_interval_ms()),
      queued: Keyword.get(opts, :queued, &Runner.queued/3),
      run: Keyword.get_lazy(opts, :run, fn -> default_run(Keyword.fetch!(opts, :run_lock)) end),
      run_lock: run_lock,
      sweep: Keyword.get(opts, :sweep, &Runner.sweep/2)
    }

    {:ok, state, {:continue, :start_listening}}
  end

  @impl GenServer
  def handle_continue(:start_listening, state) do
    if state.run_lock do
      # While the database is away the worker waits here, running nothing and crashing on nothing.
      RunLock.await_connected(state.run_lock)
      RunLock.release_all(state.run_lock)
    end

    if state.notifications, do: listen_for_writes(state.notifications)

    schedule_poll(state.poll_interval_ms)

    # A sweep at once rather than at the first poll, so the run a predecessor left is failed now.
    # No look yet: a job that takes down the process running it would take down each worker that
    # restarts, one after the other, past the supervisor's limit - the first wake or poll looks.
    {:noreply, sweep_at_start(state)}
  end

  @impl GenServer
  def handle_info(:wake, state) do
    {:noreply, wake_up(state, :look)}
  end

  def handle_info({:notification, _connection, _ref, _channel, _payload}, state) do
    {:noreply, wake_up(state, :look)}
  end

  def handle_info(:poll, state) do
    schedule_poll(state.poll_interval_ms)

    {:noreply, wake_up(state, :sweep)}
  end

  defp default_poll_interval_ms do
    :hologram
    |> Application.get_env(:job, [])
    |> Keyword.get(:poll_interval_ms, @default_poll_interval_ms)
  end

  defp default_run(run_lock), do: &Runner.process(&1, &2, run_lock)

  # Every announcement and every nudge asks the same question, so the ones already waiting are
  # answered by the look about to run. The poll is left where it is: dropping it would stop the
  # timer that keeps asking.
  defp drain_wakes do
    receive do
      :wake -> drain_wakes()
      {:notification, _connection, _ref, _channel, _payload} -> drain_wakes()
    after
      0 -> :ok
    end
  end

  # One job of each type a round, oldest first within a type and the types in module order, for as
  # long as any type has one: a type whose jobs keep coming gets one turn a round, so it never holds
  # up the types after it. Each job is asked for afresh, so one another node claimed meanwhile
  # costs no claim that is bound to be refused.
  defp fill(state, job_types) do
    {state, ran_any?} =
      Enum.reduce(job_types, {state, false}, fn job_type, {state, ran_any?} ->
        case state.queued.(job_type, state.passed_over, 1) do
          [] -> {state, ran_any?}
          [job] -> {run_job(state, job_type, job.id), true}
        end
      end)

    if ran_any?, do: fill(state, job_types), else: state
  end

  # The job types come off the mapping rather than from a sweep of the loaded modules: a sweep
  # costs tens of milliseconds and this runs on every write, while the mapping is derived once at
  # boot and re-derived exactly when the model changes. They are also the right set - a worker
  # scans tables, and the mapping is what says which tables there are.
  defp job_types do
    DB.mapping()
    |> Map.keys()
    |> Enum.filter(&Reflection.job?/1)
    |> Enum.sort()
  end

  # Every write announces itself on the log's channel, jobs included - and PostgreSQL delivers a
  # notification only once the transaction that sent it commits, which is what makes "after the
  # batch commits" a property of the mechanism rather than something to check.
  defp listen_for_writes(notifications) do
    case Listener.listen(notifications, Oplog.channel()) do
      {:ok, _ref} -> :ok
      {:eventually, _ref} -> :ok
    end
  end

  # A job left queued - its run lock held by another session, or its claim refused by a hold on the
  # data model - is left out of the looks until the next wake or poll: asked for again at once, it
  # would be answered the same way, for as long as the lock or the hold lasts. One another worker
  # took is not, since it is not queued any more and no look answers it again.
  #
  # A data model under a hold can't be read until it is released (see
  # Hologram.Entity.Model.hold/0). A claim it refuses leaves the row queued. A run whose outcome
  # write it refuses has given up its run lock with the row still running, and a sweep after the
  # hold fails it as cut short.
  defp run_job(state, job_type, id) do
    result =
      try do
        state.run.(job_type, id)
      rescue
        Hologram.StaleModelError -> :held
      end

    if result in [:held, :locked] do
      %{state | passed_over: MapSet.put(state.passed_over, id)}
    else
      state
    end
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  # Only an earlier go at what the poll's sweep does anyway, so a sweep that raises - a hold on the
  # data model, a pool not up yet, a database refusing the write - is left to the poll rather than
  # crashing each worker that restarts, one after the other, past the supervisor's limit.
  defp sweep_at_start(state) do
    :ok = state.sweep.(job_types(), MapSet.new())

    state
  rescue
    _error -> state
  end

  # Every wake and poll starts with nothing passed over, so a job left queued is tried again then.
  # The poll also sweeps: the runs cut short on other nodes are failed within one poll interval.
  # Not on every wake, since a wake comes with every write, claims and outcomes included, and a
  # sweep costs a transaction per running row.
  defp wake_up(state, look_or_sweep) do
    # Draining first is what makes the drain safe: the look after it reads the queue as it stands
    # by then, so the wakes dropped here asked for nothing it will not do. A wake arriving after
    # the read stays in the mailbox and gets its own look, which is the job created while this one
    # was working.
    drain_wakes()

    state = %{state | passed_over: MapSet.new()}
    job_types = job_types()

    if look_or_sweep == :sweep, do: :ok = state.sweep.(job_types, MapSet.new())

    fill(state, job_types)
  rescue
    # A data model under a hold can't be read until it is released (see
    # Hologram.Entity.Model.hold/0). The look is skipped rather than crashed, which would restart
    # this process on every wake for as long as the hold stands, and the next poll or wake looks
    # again.
    Hologram.StaleModelError -> state
  end
end
