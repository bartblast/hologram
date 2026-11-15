defmodule Hologram.Job.Supervisor do
  @moduledoc false

  # The worker, the connection it hears writes on and the one it holds its run locks on.
  #
  # rest_for_one, so either connection ending takes the worker with it. A worker left standing
  # would keep waiting on a listener that is gone, which nothing reports: it would fall back to its
  # poll and simply be slower for good. And one whose lock connection ended would carry on with a
  # run whose lock went with the session - a run every other node takes to be abandoned.
  #
  # A database that is away takes down nothing here. Both connections wait for it rather than
  # failing (see Hologram.DB.Config.held_connection_opts/1), and the worker waits for its lock
  # connection as it starts, so nothing crashes meanwhile. A drop ends each process that sees it
  # once, and each counts as a restart: both connections, and the worker too when it was inside a
  # transaction on the pool - three at most, within the limit of 3 in 5 seconds, and the worker
  # that replaces them waits rather than crashing again. A worker whose lock connection is up but
  # whose pool is not yet crashes on each pass, once per poll and checkout, about 9 seconds.

  use Supervisor

  alias Hologram.DB.Listener
  alias Hologram.Job.RunLock
  alias Hologram.Job.Worker

  @notifications Hologram.Job.Notifications

  @doc """
  Returns the name of the connection writes are heard on.
  """
  @spec notifications() :: atom
  def notifications, do: @notifications

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
      {Worker, name: Worker, notifications: @notifications, run_lock: RunLock}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
