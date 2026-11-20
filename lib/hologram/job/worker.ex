defmodule Hologram.Job.Worker do
  @moduledoc false

  # Runs queued jobs as they are announced, each job type up to its limit at once (see
  # Hologram.Job.max_concurrency/1), each run in a task of its own. One of these runs per node, and
  # two nodes need no agreement because a claim is a locked row: whichever reads it first runs it,
  # and the other is told it is taken.
  #
  # The runs are tasks under a supervisor of their own (Hologram.Job.Supervisor's Runs), started
  # unlinked: a run that crashes or is killed ends only itself, and the worker hears it end as a
  # reply or as a DOWN. A run's lock is its claim's and its process/3's to give up, and the worker
  # gives it up once more for a run that went down, which may have ended before its own release.
  # So the worker holds no lock of its own, and nothing it does needs a restart to free one.

  use GenServer

  require Logger

  alias Hologram.DB
  alias Hologram.DB.Listener
  alias Hologram.DB.Oplog
  alias Hologram.Job
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
  one a job still runs, no sooner than `:poll_interval_ms` after it was created. That's 5 seconds
  unless the option says otherwise, which only tests do.

  `:run_lock` names the Hologram.Job.RunLock connection the runs hold their run locks on. The
  worker waits for it to connect, then gives up every lock it holds as it starts: a worker
  restarted on its own finds its predecessor's still held on a session that is still up, and the
  rows of the runs that went with it would look live for good.

  `:runs` names the Task.Supervisor the runs are started under. It is required. The worker kills
  every run still under it as it starts, before giving the locks up: a run its predecessor left
  would otherwise go on with its lock gone.

  `:queued`, `:sweep`, `:run`, `:release` and `:max_concurrency` are what the worker looks for
  jobs, fails runs cut short, runs a job, gives up a run's lock and reads a job type's limit with.
  They default to `Hologram.Job.Runner.queued/3`, `Hologram.Job.Runner.sweep/2`,
  `Hologram.Job.Runner.process/3`, `Hologram.Job.RunLock.release/2` of the run's lock name (see
  `Hologram.Job.Runner.lock_name/2`) and `Hologram.Job.max_concurrency/1`, the run and the release
  on the `:run_lock` connection, so `:run_lock` is required unless both `:run` and `:release` are
  given. Only tests give them: the seams are what let this process be exercised without a
  database, the way the dispatcher takes the handler it routes through.
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
      max_concurrency: Keyword.get(opts, :max_concurrency, &Job.max_concurrency/1),
      notifications: Keyword.get(opts, :notifications),
      gone_down: MapSet.new(),
      passed_over: MapSet.new(),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms),
      queued: Keyword.get(opts, :queued, &Runner.queued/3),
      release:
        Keyword.get_lazy(opts, :release, fn ->
          default_release(Keyword.fetch!(opts, :run_lock))
        end),
      run: Keyword.get_lazy(opts, :run, fn -> default_run(Keyword.fetch!(opts, :run_lock)) end),
      run_lock: run_lock,
      runs: %{},
      runs_supervisor: Keyword.fetch!(opts, :runs),
      sweep: Keyword.get(opts, :sweep, &Runner.sweep/2)
    }

    {:ok, state, {:continue, :start_listening}}
  end

  @impl GenServer
  def handle_continue(:start_listening, state) do
    # Before the locks are given up, since a run left going would carry on with its lock gone - a
    # run every other node takes to be abandoned.
    kill_runs(state.runs_supervisor)

    if state.run_lock do
      # While the database is away the worker waits here, running nothing and crashing on nothing.
      RunLock.await_connected(state.run_lock)
      RunLock.release_all(state.run_lock)
    end

    if state.notifications, do: listen_for_writes(state.notifications)

    schedule_poll(state.poll_interval_ms)

    # A sweep and a look at once rather than at the first poll: the runs a predecessor left are
    # failed now, and the jobs queued while no worker ran start now. Quiet about what fails, since
    # each is only an earlier go at what the first poll does and logs: a worker can start before
    # the job tables are there - in a test env, whose test helper converges the schema after the
    # app starts - and an error logged then would only be noise.
    with {:ok, job_types} <- guard(&job_types/0, :quiet),
         swept when swept != :stop <-
           guard(fn -> state.sweep.(job_types, MapSet.new()) end, :quiet) do
      {:noreply, fill(state, job_types, :quiet)}
    else
      _stop_or_skip -> {:noreply, state}
    end
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

  # A run that answered. Its slot is free, so the look that follows fills it - its own type's
  # alone, since only that type's slot freed. A type a failed look left unasked waits for the next
  # wake or poll, which every write brings.
  #
  # A job left queued - its run lock held by another session, or its claim refused by a hold on the
  # data model - is left out of the looks until the next wake or poll: asked for again at once, it
  # would be answered the same way, for as long as the lock or the hold lasts. One another worker
  # took is not, since it is not queued any more and no look answers it again.
  def handle_info({ref, result}, state) when is_map_key(state.runs, ref) do
    Process.demonitor(ref, [:flush])

    {{job_type, id}, runs} = Map.pop!(state.runs, ref)
    ended_state = %{state | runs: runs}

    if result in [:held, :locked] do
      passed_state = pass_over(ended_state, job_type, id)

      {:noreply, fill(passed_state, [job_type])}
    else
      {:noreply, fill(ended_state, [job_type])}
    end
  end

  # A run that went down without answering: it raised past what process/3 catches - a claim or an
  # outcome write the database refused - or something killed it, or a process linked to it ended.
  # Its lock is given up here, since a run killed never reached its own release, and one given up
  # already is answered with a warning PostgreSQL sends and the connection ignores. The one case a
  # second release costs something is a run lock key two jobs share, with both run here at once:
  # it frees the other run's lock, which stacked under this one - a 64-bit hash colliding.
  #
  # A claim that went down leaves its row queued, so the job is left out of the looks until the
  # next poll, or it would be claimed again at once, going down the same way each time - with a
  # crash report, a release and a sweep for each. Not until the next wake, as a job left queued
  # under a lock is: a wake comes with every write, this node's own claims and outcomes included,
  # so a claim going down each time would be tried at the rate the app writes. A run that went down
  # on a pool that couldn't hand over a connection is the exception, left out until the next wake
  # only: the pool is busiest under the load that brings the most wakes, and the job would
  # otherwise wait a poll interval for a wait that is most likely over. A run that went down
  # after its claim leaves its row running with no lock held, so its type is swept now rather than
  # at the next poll.
  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.runs, ref) do
    {{job_type, id}, runs} = Map.pop!(state.runs, ref)

    :ok = state.release.(job_type, id)

    state =
      case reason do
        {%DBConnection.ConnectionError{}, _stacktrace} ->
          pass_over(%{state | runs: runs}, job_type, id)

        _other ->
          %{state | gone_down: MapSet.put(state.gone_down, {job_type, id}), runs: runs}
      end

    case guard(fn -> state.sweep.([job_type], running_ids(state.runs, job_type)) end) do
      {:ok, :ok} -> {:noreply, fill(state, [job_type])}
      _stop_or_skip -> {:noreply, state}
    end
  end

  defp default_release(run_lock), do: &RunLock.release(run_lock, Runner.lock_name(&1, &2))

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

  # Fills each given job type's free slots with its oldest queued jobs, the types in module order.
  # Each type has slots of its own, so a type running at its limit holds up no other type.
  #
  # A look that fails for a reason every type shares - a hold on the data model, a pool that can't
  # hand over a connection - stops the fill where it is, keeping the runs it started, since the
  # types after it would fail the same way. One that fails for a reason of its own type's, like an
  # error on its table, skips that type alone, so it doesn't hold up the types after it. The next
  # wake or poll looks again, and a run that ends looks again at its own type.
  defp fill(state, job_types, logging \\ :logged) do
    Enum.reduce_while(job_types, state, &fill_type(&2, &1, logging))
  end

  # The skip set holds the type's own jobs alone - its runs, and the ones left out of the looks for
  # now. An id is unique only within its type's table, and a browser picks the id of a row it
  # creates, so a job of another type can hold the same id: skipping it would hold up a job that
  # never failed.
  #
  # The limit is read inside the guard, like the look: a job type whose module is gone - deleted in
  # dev while one of its runs was in flight - raises reading it, and crashing on that would kill
  # every other run on the node.
  defp fill_type(state, job_type, logging) do
    left_out =
      for {^job_type, id} <- MapSet.union(state.passed_over, state.gone_down),
          into: MapSet.new(),
          do: id

    skip_ids =
      state.runs
      |> running_ids(job_type)
      |> MapSet.union(left_out)

    look = fn ->
      free = state.max_concurrency.(job_type) - running_count(state, job_type)

      if free > 0, do: state.queued.(job_type, skip_ids, free), else: []
    end

    case guard(look, logging) do
      {:ok, jobs} -> {:cont, Enum.reduce(jobs, state, &start_run(&2, job_type, &1.id))}
      :skip -> {:cont, state}
      :stop -> {:halt, state}
    end
  end

  # Runs the given function, and answers :stop or :skip instead of raising: a look or a sweep that
  # fails is left to the next wake or poll, rather than crashed on. :stop for a failure every look
  # would meet, :skip for any other. A crash would kill every run on the node through the kill as
  # the next worker starts (see kill_runs/1), for a failure another try most likely gets past - a
  # data model under a hold, which can't be read until it is released (see
  # Hologram.Entity.Model.hold/0), a pool that couldn't hand over a connection, a connection the
  # server ended under the look. And a failure that keeps coming would crash each worker that
  # restarts, one after the other, past the supervisor's limit. Exits are not caught: a lock
  # connection gone is the supervisor's to restart, with the runs, and so is a pool that is down
  # rather than busy. With :quiet, nothing is logged.
  defp guard(fun, logging \\ :logged) do
    {:ok, fun.()}
  rescue
    Hologram.StaleModelError ->
      :stop

    error in DBConnection.ConnectionError ->
      if logging == :logged do
        Logger.warning(
          "Hologram: the job worker couldn't get a database connection, and looks again at the " <>
            "next wake or poll: " <> Exception.message(error)
        )
      end

      :stop

    error ->
      if logging == :logged do
        Logger.error(
          "Hologram: the job worker failed to look for jobs or to fail the runs cut short, and " <>
            "tries again at the next wake or poll: " <>
            Exception.format(:error, error, __STACKTRACE__)
        )
      end

      :skip
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

  # Synchronous, and untrappable, since the runs are started with :brutal_kill: once this returns
  # no run of a predecessor is left. A run that ended meanwhile is not found, which is fine.
  defp kill_runs(runs_supervisor) do
    runs_supervisor
    |> Task.Supervisor.children()
    |> Enum.each(&Task.Supervisor.terminate_child(runs_supervisor, &1))
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

  defp pass_over(state, job_type, id) do
    %{state | passed_over: MapSet.put(state.passed_over, {job_type, id})}
  end

  # A model hold refuses a claim before it changes anything, so the row stays queued. A hold that
  # refuses the outcome write leaves the row running with the lock given up by process/3, and a
  # sweep after the hold fails it as cut short.
  defp run(run, job_type, id) do
    run.(job_type, id)
  rescue
    Hologram.StaleModelError -> :held
  end

  defp running_count(state, job_type) do
    Enum.count(state.runs, fn {_ref, {running_type, _id}} -> running_type == job_type end)
  end

  # The jobs this node runs, whose locks its own session holds: a sweep would find them held, and a
  # look must not start one twice. The ids of every type's runs, or of one type's.
  defp running_ids(runs) do
    MapSet.new(runs, fn {_ref, {_job_type, id}} -> id end)
  end

  defp running_ids(runs, job_type) do
    for {_ref, {^job_type, id}} <- runs, into: MapSet.new(), do: id
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  # Killed outright when the worker kills the runs as it starts, or when the unit stops, so a run/1
  # trapping exits can't hold either up.
  defp start_run(state, job_type, id) do
    run = state.run

    task =
      Task.Supervisor.async_nolink(state.runs_supervisor, fn -> run(run, job_type, id) end,
        shutdown: :brutal_kill
      )

    %{state | runs: Map.put(state.runs, task.ref, {job_type, id})}
  end

  defp sweep_if(state, job_types, :sweep) do
    guard(fn -> state.sweep.(job_types, running_ids(state.runs)) end)
  end

  defp sweep_if(_state, _job_types, :look), do: {:ok, :ok}

  # Every wake and poll starts with nothing passed over, so a job left queued is tried again then,
  # and every poll with no claim that went down left out (see the DOWN handler). The poll also
  # sweeps: the runs cut short on other nodes are failed within one poll interval.
  # Not on every wake, since a wake comes with every write, claims and outcomes included, and a
  # sweep costs a transaction per running row.
  defp wake_up(state, look_or_sweep) do
    # Draining first is what makes the drain safe: the look after it reads the queue as it stands
    # by then, so the wakes dropped here asked for nothing it will not do. A wake arriving after
    # the read stays in the mailbox and gets its own look, which is the job created while this one
    # was working.
    drain_wakes()

    state =
      case look_or_sweep do
        :sweep -> %{state | gone_down: MapSet.new(), passed_over: MapSet.new()}
        :look -> %{state | passed_over: MapSet.new()}
      end

    # A sweep that fails for a reason of one type's own still lets the look run.
    with {:ok, job_types} <- guard(&job_types/0),
         swept when swept != :stop <- sweep_if(state, job_types, look_or_sweep) do
      fill(state, job_types)
    else
      _stop_or_skip -> state
    end
  end
end
