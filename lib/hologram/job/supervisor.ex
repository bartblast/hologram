defmodule Hologram.Job.Supervisor do
  @moduledoc false

  # The worker, the connection it hears writes on and the one it holds its run locks on.
  #
  # rest_for_one, so either connection ending takes the worker with it. A worker left standing
  # would keep waiting on a listener that is gone, which nothing reports: it would fall back to its
  # poll and simply be slower for good. And one whose lock connection ended would carry on with a
  # run whose lock went with the session - a run every other node takes to be abandoned.

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
