defmodule Hologram.Job.Worker do
  @moduledoc false

  # Runs queued jobs as they are announced, one at a time. One of these runs per node, and two
  # nodes need no agreement because a claim is a locked row: whichever reads it first runs it, and
  # the other is told it is taken.

  use GenServer

  alias Hologram.DB
  alias Hologram.DB.Oplog
  alias Hologram.Job.Runner
  alias Hologram.Reflection

  # How long a queued job can wait when the announcements stop arriving - a listener whose
  # connection died, or a pooler that drops them. It bounds nothing while they do arrive, since
  # every write announces itself and is answered at once. Policy rather than a derived figure: it
  # trades a scan per interval against how late a job can run while the announcements are missing,
  # and it is the figure the dispatcher carries for the same reason.
  @default_poll_interval_ms :timer.seconds(5)

  @doc """
  Starts the worker.

  `:notifications` names a `Postgrex.Notifications` process to hear writes on. It is optional,
  because the announcements are an optimization over the poll rather than the mechanism: without
  one a job still runs, no sooner than `:poll_interval_ms` after it was created.

  `:pass` is what one sweep of the given job types does, and answers how many jobs it ran. It
  defaults to `Hologram.Job.Runner.pass/1`, which is the only thing that passes it in production -
  the seam is what lets this process be exercised without a database, the way the dispatcher takes
  the handler it routes through.
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
    state = %{
      notifications: Keyword.get(opts, :notifications),
      pass: Keyword.get(opts, :pass, &Runner.pass/1),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, default_poll_interval_ms())
    }

    {:ok, state, {:continue, :start_listening}}
  end

  @impl GenServer
  def handle_continue(:start_listening, state) do
    if state.notifications, do: listen_for_writes(state.notifications)

    schedule_poll(state.poll_interval_ms)

    {:noreply, state}
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

  defp default_poll_interval_ms do
    :hologram
    |> Application.get_env(:job, [])
    |> Keyword.get(:poll_interval_ms, @default_poll_interval_ms)
  end

  # Every announcement and every nudge asks the same question, so the ones already waiting are
  # answered by the pass about to run. The poll is left where it is: dropping it would stop the
  # timer that keeps asking.
  defp drain_wakes do
    receive do
      :wake -> drain_wakes()
      {:notification, _connection, _ref, _channel, _payload} -> drain_wakes()
    after
      0 -> :ok
    end
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
    case Postgrex.Notifications.listen(notifications, Oplog.channel()) do
      {:ok, _ref} -> :ok
      {:eventually, _ref} -> :ok
    end
  end

  # A pass that ran something is followed by another: a job created by one that just ran, or one
  # that committed while the pass worked, is picked up now rather than at the next announcement.
  defp run_passes(pass, job_types) do
    if pass.(job_types) > 0, do: run_passes(pass, job_types)
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  defp wake_up(state) do
    # Draining first is what makes the drain safe: the pass after it reads the queue as it stands
    # by then, so the wakes dropped here asked for nothing it will not do. A wake arriving after
    # the read stays in the mailbox and gets its own pass, which is the job created while this one
    # was working.
    drain_wakes()

    run_passes(state.pass, job_types())

    state
  end
end
