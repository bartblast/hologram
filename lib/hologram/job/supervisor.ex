defmodule Hologram.Job.Supervisor do
  @moduledoc false

  # The worker, the connection it hears writes on, the one its runs hold their run locks on, and
  # the supervisor the runs are tasks under.
  #
  # rest_for_one, so either connection ending takes the runs and the worker with it. A worker left
  # standing would keep waiting on a listener that is gone, which nothing reports: it would fall
  # back to its poll and simply be slower for good. And runs whose lock connection ended would
  # carry on with their locks gone with the session - runs every other node takes to be abandoned.
  # Runs sits before the worker, so the worker ending alone leaves the runs up: the worker that
  # replaces it kills them before it gives up their locks (see Hologram.Job.Worker).
  #
  # A database that is away takes down nothing here. Both connections wait for it rather than
  # failing (see Hologram.DB.Config.held_connection_opts/1), the worker waits for its lock
  # connection as it starts, and it logs a look or a sweep that fails rather than crashing on it,
  # so nothing crashes meanwhile but the runs, which aren't restarted. A drop ends each connection
  # that sees it once, and each counts as a restart - two at most, within the limit of 3 in 5
  # seconds. A lock statement the server leaves unanswered for 5 seconds, or the session settings
  # for 150, kill the lock connection, which counts once: the runs and the worker go with it. A
  # worker giving up the lock of a run that went down just then finds the connection gone and
  # crashes too, which is part of the same restart, since the supervisor is already taking it down
  # - its report of the worker's end names the missing connection. A LISTEN left unanswered for
  # 4 seconds, or the listener's first statement for 150, kills the listener the same way, taking
  # the others with it.

  use Supervisor

  alias Hologram.DB.Listener
  alias Hologram.Job.RunLock
  alias Hologram.Job.Worker

  @notifications Hologram.Job.Notifications

  @runs Hologram.Job.Runs

  @doc """
  Returns the name of the connection writes are heard on.
  """
  @spec notifications() :: atom
  def notifications, do: @notifications

  @doc """
  Returns the name of the supervisor the runs are tasks under.
  """
  @spec runs() :: atom
  def runs, do: @runs

  @doc """
  Starts the job supervision unit.
  """
  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    children = [
      {Listener, name: @notifications},
      {RunLock, name: RunLock},
      Supervisor.child_spec({Task.Supervisor, name: @runs}, id: @runs),
      {Worker, name: Worker, notifications: @notifications, run_lock: RunLock, runs: @runs}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
